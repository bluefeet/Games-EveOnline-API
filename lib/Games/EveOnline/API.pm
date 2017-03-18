package Games::EveOnline::API;
use Moo;

=head1 NAME

Games::EveOnline::API - A simple Perl wrapper around the EveOnline XML API.

=head1 SYNOPSIS

  use Games::EveOnline::API;
  my $eapi = Games::EveOnline::API->new();
  
  my $skill_groups = $eapi->skill_tree();
  my $ref_types = $eapi->ref_types();
  my $systems = $eapi->sovereignty();
  
  # The rest of the methods require authentication.
  my $eapi = Games::EveOnline::API->new( user_id=>'..', api_key=>'..' );
  
  my $characters = $eapi->characters();
  my $sheet = $eapi->character_sheet( character_id => $character_id );
  my $in_training = $eapi->skill_in_training( character_id => $character_id );

=head1 DESCRIPTION

This module provides a Perl wrapper around the Eve-Online API, version 2.
The need for the wrapper arrises for two reasons.  First, the XML that
is provided by the API is overly complex, at least for my taste.  So, other
than just returning you a perl data representation of the XML, it also
simplifies the results.

Only a couple of the methods provided by this module can be used straight
away.  The rest require that you get a user_id (keyID) and api_key (vCode).

=head1 A NOTE ON CACHING

Most of these methods return a 'cached_until' value.  I've no clue if this
is CCP telling you how long you should cache the information before you
should request it again, or if this is the point at which CCP will refresh
their cache of this information.

Either way, it is good etiquet to follow the cacheing guidelines of a
provider.  If you over-use the API I'm sure you'll eventually get blocked.

=cut

use Types::Standard qw( Int Str );

use URI;
use LWP::UserAgent qw();
use XML::Simple qw();
use XML::LibXML;
use Carp qw( croak );

=head1 ARGUMENTS

=head2 user_id

An Eve Online API user ID (also known as a keyID).

=head2 api_key

The key, as provided Eve Online, to access the API (also known
as a vCode).

=head2 character_id

Set the default C<character_id>.  Any methods that require
a characte ID, and are not given one, will use this one.

=head2 api_url

The URL that will be used to access the Eve Online API.
Defaults to L<https://api.eveonline.com>.  Normally you
won't want to change this.

=cut

has user_id      => (is=>'ro', isa=>Int );
has api_key      => (is=>'ro', isa=>Str );
has character_id => (is=>'ro', isa=>Int );
has api_url      => (is=>'ro', isa=>Str, default=>'https://api.eveonline.com');

=head1 ANONYMOUS METHODS

These methods may be called anonymously, without authentication.

=head2 skill_tree

  my $skill_groups = $eapi->skill_tree();

Returns a complex data structure containing the entire skill tree.
The data structure is:

  {
    cached_until => $date_time,
    $group_id => {
      name => $group_name,
      skills => {
        $skill_id => {
          name => $skill_name,
          description => $skill_description,
          rank => $skill_rank,
          primary_attribute => $skill_primary_attribute,
          secondary_attribute => $skill_secondary_attribute,
          bonuses => {
            $bonus_name => $bonus_value,
          },
          required_skills => {
            $skill_id => $skill_level,
          },
        }
      }
    }
  }

=cut

sub skill_tree {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path => 'eve/SkillTree.xml.aspx',
    );

    my $result = {};

    foreach my $row ($data->findnodes('/eveapi/result/rowset[@name = "skillGroups"]/row')) {
        my $group_id = $row->getAttribute('groupID');
        my $group_result = {};
        $group_result->{$group_id}->{name} = $row->getAttribute('groupName');
        $group_result->{$group_id}->{skills} = {};

        my $skill_rows;
        foreach my $skill ( $row->findnodes( './rowset[@name = "skills"]/row' ) ) {
            my $skill_id = $skill->getAttribute('typeID');
            my $skill_result = {};

            $skill_result->{name}                = $skill->getAttribute('typeName');
            $skill_result->{description}         = $skill->findnodes('./description')->to_literal->value();
            $skill_result->{rank}                = $skill->findnodes('./rank')->to_literal->value();
            $skill_result->{primary_attribute}   = $skill->findnodes('./requiredAttributes/primaryAttribute')->to_literal->value();
            $skill_result->{secondary_attribute} = $skill->findnodes('./requiredAttributes/secondaryAttribute')->to_literal->value();

            $skill_result->{bonuses} = {};
            foreach my $bonus ( $skill->findnodes("./rowset[\@name = 'skillBonusCollection']/row") ) {
                $skill_result->{bonuses}->{ $bonus->getAttribute('bonusType') } = $bonus->getAttribute('bonusValue');
            }

            $skill_result->{required_skills} = {};
            foreach my $required_skill ( $skill->findnodes("./rowset[\@name = 'requiredSkills']/row") ) {
                $skill_result->{required_skills}->{ $required_skill->getAttribute('typeID') } = $required_skill->getAttribute('skillLevel');
            }
            $group_result->{$group_id}->{skills}->{$skill_id} = $skill_result;
        }

        # More elegant solution?
        foreach my $group_key ( keys %$group_result ) {
            foreach my $skill_id ( keys %{ $group_result->{$group_key}->{skills} } ) {
                next if exists $result->{$group_key}->{skills}->{$skill_id};
                $result->{$group_id}->{name} = $group_result->{$group_key}->{name};
                $result->{$group_id}->{skills}->{$skill_id} = $group_result->{$group_key}->{skills}->{$skill_id};
            }
        }
    }

    $result->{cached_until} = $data->findnodes('/eveapi/cachedUntil')->to_literal->value();

    return $result;
}

=head2 ref_types

  my $ref_types = $eapi->ref_types();

Returns a simple hash structure containing definitions of the
various financial transaction types.  This is useful when pulling
wallet information. The key of the hash is the ref type's ID, and
the value of the title of the ref type.

=cut

sub ref_types {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path => 'eve/RefTypes.xml.aspx',
    );

    return $self->_get_error( $data ) if defined $data->{error};

    my $ref_types = {};

    my $rows = $data->{result}->{rowset}->{row};
    foreach my $ref_type_id (keys %$rows) {
        $ref_types->{$ref_type_id} = $rows->{$ref_type_id}->{refTypeName};
    }

    $ref_types->{cached_until} = $data->{cachedUntil};

    return $ref_types;
}

=head2 sovereignty

  my $systems = $eapi->sovereignty();

Returns a hashref where each key is the system ID, and the
value is a hashref with the keys:

  name
  faction_id
  sovereignty_level
  constellation_sovereignty
  alliance_id

=cut

sub sovereignty {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path => 'map/Sovereignty.xml.aspx',
    );

    return $self->_get_error( $data ) if defined $data->{error};

    my $systems = {};

    my $rows = $data->{result}->{rowset}->{row};
    foreach my $system_id (keys %$rows) {
        my $system = $systems->{$system_id} = {};
        $system->{name}                      = $rows->{$system_id}->{solarSystemName};
        $system->{faction_id}                = $rows->{$system_id}->{factionID};
        $system->{sovereignty_level}         = $rows->{$system_id}->{sovereigntyLevel};
        $system->{constellation_sovereignty} = $rows->{$system_id}->{constellationSovereignty};
        $system->{alliance_id}               = $rows->{$system_id}->{allianceID};
    }

    $systems->{cached_until} = $data->{cachedUntil};
    $systems->{data_time}    = $data->{result}->{dataTime};

    return $systems;
}

=head1 RESTRICTED METHODS

These methods require authentication to use, so you must have set
the L</user_id> and L</api_key> arguments to use them.

=head2 characters

  my $characters = $eapi->characters();

Returns a hashref where key is the character ID and the
value is a hashref with a couple bits about the character.
Here's a sample:

  {
    '1972081734' => {
      'corporation_name' => 'Bellator Apparatus',
      'corporation_id'   => '1044143901',
      'name'             => 'Ardent Dawn'
    }
  }

=cut

sub characters {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path          => 'account/Characters.xml.aspx',
        requires_auth => 1,
    );

    return $self->_get_error( $data ) if defined $data->{error};

    my $characters = {};
    my $rows = $data->{result}->{rowset}->{row};

    foreach my $character_id (keys %$rows) {
        $characters->{$character_id} = {
            name             => $rows->{$character_id}->{name},
            corporation_name => $rows->{$character_id}->{corporationName},
            corporation_id   => $rows->{$character_id}->{corporationID},
        };
    }

    $characters->{cached_until} = $data->{cachedUntil};

    return $characters;
}

=head2 character_sheet

  my $sheet = $eapi->character_sheet( character_id => $character_id );

For the given character ID a hashref is returned with
the all the information about the character.  Here's
a sample:

  {
    'name'             => 'Ardent Dawn',
    'balance'          => '99010910.10',
    'race'             => 'Amarr',
    'blood_line'       => 'Amarr',
    'corporation_name' => 'Bellator Apparatus',
    'corporation_id'   => '1044143901',
  
    'skills' => {
      '3455' => {
        'level'        => '2',
        'skill_points' => '1415'
      },
      # Removed the rest of the skills for readability.
    },
  
    'attribute_enhancers' => {
      'memory' => {
        'value' => '3',
        'name'  => 'Memory Augmentation - Basic'
      },
      # Removed the rest of the enhancers for readability.
    },
  
    'attributes' => {
      'memory'       => '7',
      'intelligence' => '7',
      'perception'   => '4',
      'charisma'     => '4',
      'willpower'    => '17'
    }
  }

=cut

sub character_sheet {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/CharacterSheet.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );

    return $self->_get_error( $data ) if defined $data->{error};

    my $result = $data->{result};

    my $sheet           = {};
    my $implants        = {};
    my $jump_clones     = {};
    my $jump_clone_imps = {};

    # implants
    foreach my $imp_id (  keys %{ $result->{rowset}->{implants}->{row} } ) {
        $implants->{$imp_id} = $result->{rowset}->{implants}->{row}->{$imp_id}->{typeName};
    }

    # jump clones
    foreach my $clone_id (  keys %{ $result->{rowset}->{jumpClones}->{row} } ) {
        $jump_clones->{$clone_id} = 
          {
              type_id     => $result->{rowset}->{jumpClones}->{row}->{$clone_id}->{typeID},
              location_id => $result->{rowset}->{jumpClones}->{row}->{$clone_id}->{locationID},
              clone_name  => $result->{rowset}->{jumpClones}->{row}->{$clone_id}->{cloneName},
          };
    }

    # TODO: jump clone implants
    
    $sheet = {
        character_id        => $result->{characterID},
        date_of_birth       => $result->{DoB},
        ancestry            => $result->{ancestry},
        gender              => $result->{gender},
        clone_type_id       => undef, # deleted in Rhea
        clone_name          => undef, # deleted in Rhea
        clone_skill_points  => undef, # deleted in Rhea
        clone_jump_date     => $result->{cloneJumpDate},
        free_skill_points   => $result->{freeSkillPoints},
        free_respecs        => $result->{freeRespecs},
        last_respec_date    => $result->{lastRespecDate},
        last_timed_respec   => $result->{lastTimedRespec},
        remote_station_date => $result->{remoteStationDate},
        blood_line          => $result->{bloodLine},
        name                => $result->{name},
        corporation_id      => $result->{corporationID},
        corporation_name    => $result->{corporationName},
        balance             => $result->{balance},
        race                => $result->{race},
        attributes          => $result->{attributes},
        jump_activation     => $result->{jumpActivation},
        jump_fatigue        => $result->{jumpFatigue},
        jump_last_update    => $result->{jumpLastUpdate},
        home_station_id     => $result->{homeStationID},
        attribute_enhancers => {}, # deprecated key
        implants            => $implants,
        jump_clones         => $jump_clones,
        jump_clone_implants => $jump_clone_imps,
        cached_until        => $data->{cachedUntil},
    };

    my $skills     = $sheet->{skills} = {};
    my $skill_rows = $result->{rowset}->{skills}->{row};
    foreach my $skill_id (keys %$skill_rows) {
        my $skill = $skills->{$skill_id} = {};

        $skill->{level}        = $skill_rows->{$skill_id}->{level};
        $skill->{skill_points} = $skill_rows->{$skill_id}->{skillpoints};
    }

    # TODO: Add logic to parse next rowsets:
    # certificates, corporationRoles, corporationRolesAtHQ, 
    # corporationRolesAtBase, corporationRolesAtOther, corporationTitles, jumpCloneImplants

    return $sheet;
}

=head2 skill_in_training

  my $in_training = $eapi->skill_in_training( character_id => $character_id );

Returns a hashref with the following structure:

  {
    'current_tq_time' => {
      'content' => '2008-05-10 04:06:35',
      'offset'  => '0'
    },
    'end_time'   => '2008-05-10 19:23:18',
    'start_sp'   => '139147',
    'to_level'   => '5',
    'start_time' => '2008-05-07 16:15:05',
    'skill_id'   => '3436',
    'end_sp'     => '256000'
  }

=cut

sub skill_in_training {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/SkillInTraining.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );
    my $result = $data->{result};

    return $self->_get_error( $data ) if defined $data->{error};

    my $training = {
        current_tq_time => $result->{currentTQTime},
        skill_id        => $result->{trainingTypeID},
        to_level        => $result->{trainingToLevel},
        start_time      => $result->{trainingStartTime},
        end_time        => $result->{trainingEndTime},
        start_sp        => $result->{trainingStartSP},
        end_sp          => $result->{trainingDestinationSP},
    };

    $training->{cached_until} = $data->{cachedUntil};

    return $training;
}

=head2 api_key_info

  my $api_info = $eapi->api_key_info();

Returns a hashref with the following structure:

  {
    'cached_until' => '2014-06-26 16:57:40',
    'type' => 'Account',
    'access_mask' => '268435455',
    'characters' => {
      '12345678' => {
        'faction_id' => '0',
        'character_name' => 'Char Name',
        'corporation_name' => 'School of Applied Knowledge',
        'faction_name' => '',
        'alliance_id' => '0',
        'corporation_id' => '1000044',
        'alliance_name' => ''
      },
      '87654321' => {
        'faction_id' => '0',
        'character_name' => 'Char Name2',
        'corporation_name' => 'Corp Name',
        'faction_name' => '',
        'alliance_id' => '1234567890',
        'corporation_id' => '987654321',
        'alliance_name' => 'Alliance Name'
      }
    },
    'expires' => ''
  }

=cut

sub api_key_info {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path                  => 'account/ApiKeyInfo.xml.aspx',
        requires_auth         => 1,
    );

    my $result = $data->{result}->{key};

    return $self->_get_error( $data ) if defined $data->{error};

    my $key_info = {
        type    => $result->{type},
        expires => $result->{expires},
        access_mask => $result->{accessMask},
    };

    # TODO: add structure for corporation and alliance API
    if ( defined $result->{rowset}->{row} ) {
        $key_info->{characters} = {};
        foreach my $char_id ( keys %{ $result->{rowset}->{row} } ) {
            $key_info->{characters}->{$char_id} = {
                'character_name'   => $result->{rowset}->{row}->{$char_id}->{characterName},
                'faction_name'     => $result->{rowset}->{row}->{$char_id}->{factionName}     || '',
                'corporation_id'   => $result->{rowset}->{row}->{$char_id}->{corporationID},
                'alliance_name'    => $result->{rowset}->{row}->{$char_id}->{allianceName}    || '',
                'faction_id'       => $result->{rowset}->{row}->{$char_id}->{factionID}       || '0',
                'corporation_name' => $result->{rowset}->{row}->{$char_id}->{corporationName},
                'alliance_id'      => $result->{rowset}->{row}->{$char_id}->{allianceID}      || '0',
            };
        }
    }

    $key_info->{cached_until} = $data->{cachedUntil};

    return $key_info;
}

=head2 account_status

  my $account_status = $eapi->account_status();

Returns a hashref with the following structure:

  {
    'cachedUntil' => '2014-06-26 17:17:12',
    'logon_minutes' => '79114',
    'logon_count' => '940',
    'create_date' => '2011-06-22 11:44:37',
    'paid_until' => '2014-08-26 16:37:43'
  }

=cut

sub account_status {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path                  => 'account/AccountStatus.xml.aspx',
        requires_auth         => 1,
    );

    my $result = $data->{result};

    return $self->_get_error( $data ) if defined $data->{error};

    return {
        paid_until    => $result->{paidUntil},
        create_date   => $result->{createDate},
        logon_count   => $result->{logonCount},
        logon_minutes => $result->{logonMinutes},
        cached_until   => $data->{cachedUntil},
    }
}

=head2 character_info

  my $character_info = $eapi->character_info( character_id => $character_id );

Returns a hashref with the following structure:

  {
    'character_name' => 'Char Name',
    'alliance_id' => '1234567890',
    'corporation_id' => '987654321',
    'corporation' => 'Corp Name',
    'alliance' => 'Alliance Name',
    'race' => 'Caldari',
    'bloodline' => 'Achura',
    'skill_points' => '40955856',
    'employment_history' => {
      '23046655' => {
        'corporation_id' => '123456789',
        'start_date' => '2013-02-03 13:39:00',
        'record_id' => '23046655'
      },
      '29131760' => {
        'corporation_id' => '987654321',
        'start_date' => '2013-11-04 16:40:00',
        'record_id' => '29131760'
      },
    },
    'ship_type_id' => '670',
    'account_balance' => '38131.68',
    'cached_until' => '2014-06-26 17:18:29',
    'last_known_location' => 'Jita',
    'character_id' => '12345678',
    'alliance_date' => '2012-08-05 00:12:00',
    'corporation_date' => '2012-09-11 20:32:00',
    'ship_type_name' => 'Capsule',
    'security_status' => '1.3534973114985',
    'ship_name' => 'Char Name Capsule'
  }

=cut

sub character_info {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'eve/CharacterInfo.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );

    my $result = $data->{result};

    return $self->_get_error( $data ) if defined $data->{error};

    my $info = {
        character_id        => $result->{characterID},
        character_name      => $result->{characterName}, 
        race                => $result->{race}, 
        bloodline           => $result->{bloodline}, 
        account_balance     => $result->{accountBalance}, 
        skill_points        => $result->{skillPoints}, 
        ship_name           => $result->{shipName}, 
        ship_type_id        => $result->{shipTypeID}, 
        ship_type_name      => $result->{shipTypeName}, 
        corporation_id      => $result->{corporationID}, 
        corporation         => $result->{corporation}, 
        corporation_date    => $result->{corporationDate}, 
        alliance_id         => $result->{allianceID}, 
        alliance            => $result->{alliance}, 
        alliance_date       => $result->{allianceDate}, 
        last_known_location => $result->{lastKnownLocation}, 
        security_status     => $result->{securityStatus},
        cached_until        => $data->{cachedUntil},
    };

    if ( defined $result->{rowset}->{row} ) {
        foreach my $history_row ( @{ $result->{rowset}->{row} } ) {
            $info->{employment_history}->{$history_row->{recordID}}->{record_id}      = $history_row->{recordID};
            $info->{employment_history}->{$history_row->{recordID}}->{corporation_id} = $history_row->{corporationID};
            $info->{employment_history}->{$history_row->{recordID}}->{start_date}     = $history_row->{startDate};
        }
    }

    return $info;
}

=head2 asset_list

  my $asset_list = $eapi->asset_list( character_id => $character_id );

Returns a hashref with the following structure:

  {
    '1014951232473' => {
      'contents' => {
        '1014957890964' => {
          'type_id' => '2454',
          'quantity' => '1',
          'flag' => '87',
          'raw_quantity' => '-1',
          'singleton' => '1',
          'item_id' => '1014957890964'
        }
      },
      'quantity' => '1',
      'flag' => '4',
      'location_id' => '60014680',
      'singleton' => '1',
      'item_id' => '1014951232473',
      'type_id' => '32880',
      'raw_quantity' => '-1'
    },
    '1014951385057' => {
      'type_id' => '1178',
      'quantity' => '1',
      'flag' => '4',
      'raw_quantity' => '-2',
      'location_id' => '60015001',
      'singleton' => '1',
      'item_id' => '1014951385057'
    }
  }

=cut

sub asset_list {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/AssetList.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );

    my $result = $data->{result};

    return $self->_get_error( $data ) if defined $data->{error};

    return $self->_parse_assets( $result );
}


sub industry_jobs {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') if ! $character_id && $args{type} && $args{type} ne 'corp';

    my $type = $args{type} && $args{type} eq 'corp' ? 'corp' : 'char';

    my $data = $self->_load_xml(
        path          => "$type/IndustryJobs".($args{history} || '').".xml.aspx",
        requires_auth => 1,
        character_id  => $type eq 'char' ? $character_id : undef,
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $jobs;

    foreach my $job_id ( keys %$result ) {
        
        $jobs->{$job_id} = {
            job_id                  => $job_id,
            installer_id            => $result->{$job_id}->{installerID},
            installer_name          => $result->{$job_id}->{installerName},
            facility_id             => $result->{$job_id}->{facilityID},
            solar_system_id         => $result->{$job_id}->{solarSystemID},
            solar_system_name       => $result->{$job_id}->{solarSystemName},
            station_id              => $result->{$job_id}->{stationID},
            activity_id             => $result->{$job_id}->{activityID},
            blueprint_id            => $result->{$job_id}->{blueprintID},
            blueprint_type_id       => $result->{$job_id}->{blueprintTypeID},
            blueprint_type_name     => $result->{$job_id}->{blueprintTypeName},
            blueprint_location_id   => $result->{$job_id}->{blueprintLocationID},
            output_location_id      => $result->{$job_id}->{outputLocationID},
            runs                    => $result->{$job_id}->{runs},
            cost                    => $result->{$job_id}->{cost},
            team_id                 => $result->{$job_id}->{teamID},
            licensed_runs           => $result->{$job_id}->{licensedRuns},
            probability             => $result->{$job_id}->{probability},
            product_type_id         => $result->{$job_id}->{productTypeID},
            product_type_name       => $result->{$job_id}->{productTypeName},
            status                  => $result->{$job_id}->{status},
            time_in_seconds         => $result->{$job_id}->{timeInSeconds},
            start_date              => $result->{$job_id}->{startDate},
            end_date                => $result->{$job_id}->{endDate},
            pause_date              => $result->{$job_id}->{pauseDate},
            completed_date          => $result->{$job_id}->{completedDate},
            completed_character_id  => $result->{$job_id}->{completedCharacterID},
            successful_runs         => $result->{$job_id}->{successfulRuns},
        };
    }

    $jobs->{cached_until} = $data->{cachedUntil};
    return $jobs;

}

sub industry_jobs_history {
    my ($self, %args) = @_;

    return $self->industry_jobs(%args, history=>'History');
}

=head2 contact_list

  my $contact_list = $eapi->contact_list( character_id  => $character_id );

Returns a hashref with the following structure:

  {
    'contact_list' => {
      '962693552' => {
        'standing' => '10',
        'contact_name' => 'Char Name',
        'contact_id' => '962693552',
        'in_watchlist' => undef,
        'contact_type_id' => '1384'
      },
      '3019494' => {
        'standing' => '0',
        'contact_name' => 'Char Name 3',
        'contact_id' => '3019494',
        'in_watchlist' => undef,
        'contact_type_id' => '1375'
      },
      '1879838281' => {
        'standing' => '10',
        'contact_name' => 'Char Name 2',
        'contact_id' => '1879838281',
        'in_watchlist' => undef,
        'contact_type_id' => '1378'
      }
    }
  }

=cut

sub contact_list {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') if ! $character_id && $args{type} && $args{type} ne 'corp';

    my $type = $args{type} && $args{type} eq 'corp' ? 'corp' : 'char';

    my $data = $self->_load_xml(
        path          => "$type/ContactList.xml.aspx",
        requires_auth => 1,
        character_id  => $type eq 'char' ? $character_id : undef,
    );

    my $result = $data->{result};

    return $self->_get_error( $data ) if defined $data->{error};

    my $contacts;
    foreach my $rows ( keys %{$result->{rowset}} ) {
        next unless defined $result->{rowset}->{$rows}->{row};
        my $key = $rows; 
        $key =~ s/L/_l/;
        $key =~ s/C/_c/; # TODO: more correctly regexp
        foreach my $contact_id ( keys %{ $result->{rowset}->{$rows}->{row} } ) {
            $contacts->{$key}->{$contact_id}->{contact_id}      = $contact_id;
            $contacts->{$key}->{$contact_id}->{standing}        = $result->{rowset}->{$rows}->{row}->{$contact_id}->{standing};
            $contacts->{$key}->{$contact_id}->{contact_name}    = $result->{rowset}->{$rows}->{row}->{$contact_id}->{contactName};
            $contacts->{$key}->{$contact_id}->{contact_type_id} = $result->{rowset}->{$rows}->{row}->{$contact_id}->{contactTypeID};
            if ( $rows eq 'contactList' ) {
                $contacts->{$key}->{$contact_id}->{in_watchlist} = $result->{rowset}->{$rows}->{row}->{$contact_id}->{inWatchlist};
            }
        }
    }

    $contacts->{cached_until} = $data->{cachedUntil};

    return $contacts;
}

=head2 wallet_transactions

  my $wallet_transactions = $eapi->wallet_transactions( 
        character_id  => $character_id, 
        row_count     => $row_count,      # optional, default is 2560
        account_key   => $account_key,    # optional, default is 1000
        from_id       => $args{from_id},  # optional, need for offset
      );

Returns a hashref with the following structure:

  {
    '3499165305' => {
      'type_name' => 'Mining Frigate',
      'quantity' => '1',
      'client_id' => '90646537',
      'transaction_date_time' => '2014-06-28 12:23:41',
      'station_id' => '60015001',
      'transaction_id' => '3499165305',
      'transaction_for' => 'personal',
      'type_id' => '32918',
      'station_name' => 'Akiainavas III - School of Applied Knowledge',
      'client_name' => 'Zeta Zhang',
      'price' => '1201.02',
      'transaction_type' => 'sell'
    },
    '3482136396' => {
      'type_name' => 'Mining Barge',
      'quantity' => '1',
      'client_id' => '1000167',
      'transaction_date_time' => '2014-06-15 20:15:26',
      'station_id' => '60014680',
      'transaction_id' => '3482136396',
      'transaction_for' => 'personal',
      'type_id' => '17940',
      'station_name' => 'Autama V - Moon 9 - State War Academy',
      'client_name' => 'State War Academy',
      'price' => '500000.00',
      'transaction_type' => 'buy'
    }
  }

=cut

sub wallet_transactions {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $row_count   = $args{row_count}   || 2560;
    my $account_key = $args{account_key} || 1000;


    my $data = $self->_load_xml(
        path          => 'char/WalletTransactions.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
        row_count     => $row_count,
        account_key   => $account_key,
        from_id       => $args{from_id},
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $trans;
    foreach my $t_id ( keys %$result ) {
        $trans->{$t_id} = {
            transaction_for       => $result->{$t_id}->{transactionFor},
            transaction_type      => $result->{$t_id}->{transactionType},
            station_name          => $result->{$t_id}->{stationName},
            station_id            => $result->{$t_id}->{stationID},
            client_name           => $result->{$t_id}->{clientName},
            client_id             => $result->{$t_id}->{clientID},
            price                 => $result->{$t_id}->{price},
            type_id               => $result->{$t_id}->{typeID},
            type_name             => $result->{$t_id}->{typeName},
            quantity              => $result->{$t_id}->{quantity},
            transaction_id        => $t_id,
            transaction_date_time => $result->{$t_id}->{transactionDateTime},
        };
    }

    $trans->{cached_until} = $data->{cachedUntil};

    return $trans;
}

=head2 wallet_journal

  my $wallet_journal = $eapi->wallet_journal( 
        character_id  => $character_id, 
        row_count     => $row_count,      # optional, default is 2560
        account_key   => $account_key,    # optional, default is 1000
        from_id       => $args{from_id},  # optional, need for offset
      );

Returns a hashref with the following structure:

  {
    '9729070529' => {
                'owner_name2' => 'Milolika Muvila',
                'arg_id1' => '0',
                'date' => '2014-07-08 19:02:53',
                'reason' => '',
                'tax_receiver_id' => '',
                'owner_name1' => 'Cyno Chain',
                'amount' => '814900000.00',
                'owner_id1' => '93496706',
                'tax_amount' => '',
                'balance' => '826371087.94',
                'arg_name1' => '3513456219',
                'ref_id' => '9729070529',
                'ref_type_id' => '2',
                'owner_id2' => '94701913'
              },
    '9729071394' => {
                'owner_name2' => '',
                'arg_id1' => '0',
                'date' => '2014-07-08 19:03:04',
                'reason' => '',
                'tax_receiver_id' => '',
                'owner_name1' => 'Milolika Muvila',
                'amount' => '-28369982.50',
                'owner_id1' => '94701913',
                'tax_amount' => '',
                'balance' => '785777605.44',
                'arg_name1' => '',
                'ref_id' => '9729071394',
                'ref_type_id' => '42',
                'owner_id2' => '0'
              }
  }

=cut

sub wallet_journal {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $row_count   = $args{row_count}   || 2560;
    my $account_key = $args{account_key} || 1000;


    my $data = $self->_load_xml(
        path          => 'char/WalletJournal.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
        row_count     => $row_count,
        account_key   => $account_key,
        from_id       => $args{from_id},
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $journal;
    foreach my $r_id ( keys %$result ) {
        $journal->{$r_id} = {
            ref_id          => $r_id,
            date            => $result->{$r_id}->{date},
            ref_type_id     => $result->{$r_id}->{refTypeID},
            owner_name1     => $result->{$r_id}->{ownerName1},
            owner_id1       => $result->{$r_id}->{ownerID1},
            owner_name2     => $result->{$r_id}->{ownerName2},
            owner_id2       => $result->{$r_id}->{ownerID2},
            arg_name1       => $result->{$r_id}->{argName1},
            arg_id1         => $result->{$r_id}->{argID1},
            amount          => $result->{$r_id}->{amount},
            balance         => $result->{$r_id}->{balance},
            reason          => $result->{$r_id}->{reason},
            tax_amount      => $result->{$r_id}->{taxAmount},
            tax_receiver_id => $result->{$r_id}->{taxReceiverID},
        };
    }

    $journal->{cached_until} = $data->{cachedUntil};

    return $journal;
}

=head2 mail_messages

  my $mail_messages = $eapi->mail_messages( character_id  => $character_id );

Returns a hashref with the following structure:

{
  '331477595' => {
                 'to_list_id' => '145156607',
                 'message_id' => '331477595',
                 'to_character_ids' => '',
                 'sender_id' => '91669871',
                 'sent_date' => '2013-10-08 06:30:00',
                 'to_corp_or_alliance_id' => '',
                 'title' => "\x{420}\x{430}\x{441}\x{43f}\x{440}\x{43e}\x{434}\x{430}\x{436}\x{430}",
                 'sender_name' => 'Valerii Ostudnev'
               },
  '336393982' => {
                 'to_list_id' => '',
                 'message_id' => '336393982',
                 'to_character_ids' => '1203082547',
                 'sender_id' => '90922771',
                 'sent_date' => '2014-03-02 13:30:00',
                 'to_corp_or_alliance_id' => '',
                 'title' => 'TSG -&gt; Z-H',
                 'sender_name' => 'Chips Merkaba'
               },
  'cached_until' => '2014-07-10 18:33:59'
}

=cut

sub mail_messages {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/MailMessages.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $messages;
  
    foreach my $mes_id ( keys %$result ) {
        $messages->{$mes_id} = {
            message_id              => $mes_id,
            sender_id               => $result->{$mes_id}->{senderID},
            sender_name             => $result->{$mes_id}->{senderName},
            sent_date               => $result->{$mes_id}->{sentDate},
            title                   => $result->{$mes_id}->{title},
            to_corp_or_alliance_id  => $result->{$mes_id}->{toCorpOrAllianceID},
            to_character_ids        => $result->{$mes_id}->{toCharacterIDs},
            to_list_id              => $result->{$mes_id}->{toListID},
        };
    }
    $messages->{cached_until} = $data->{cachedUntil};

    return $messages;
}

=head2 mail_bodies

  my $mail_bodies = $eapi->mail_bodies( character_id  => $character_id, ids => $ids );

Returns a hashref with the following structure:


{
  'cached_until' => '2024-07-07 18:13:16',
  'missing_message_ids' => '331477591',
  '331477595' => "<font size="12" color="#bfffffff"></font><font size="12" color="#fff7931e"><a href="contract:30004977//73497683">[Multiple Items]</a></font><font size="12" color="#bfffffff"> x{428}x{438}x{43b}x{434}x{43e}x{432}x{44b}x{439} x{43c}x{43e}x{430} 30x{43a}x{43a}<br></font><font size="12" color="#fff7931e"><a href="contract:30004977//73497661">[Multiple Items]</a></font><font size="12" color="#bfffffff"> x{410}x{440}x{442}x{438}-x{421}x{411} x{413}x{43d}x{43e}x{437}x{438}x{441} 80x{43a}x{43a}<br></font><font size="12" color="#fff7931e"><a href="contract:30004977//73497644">[Multiple Items]</a></font><font size="12" color="#bfffffff"> x{410}x{440}x{43c}x{43e}x{440}x{43d}x{44b}x{439} x{431}x{440}x{443}x{442}x{438}x{43a}x{441} 60x{43a}x{43a}</font>"
}

=cut

sub mail_bodies {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;
    croak('No comma separated messages ids specified') unless $args{ids};

    my $data = $self->_load_xml(
        path          => 'char/MailBodies.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
        ids           => $args{ids},
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $bodies;
    
    foreach my $mes_id ( keys %$result ) {
        $bodies->{$mes_id} = $result->{$mes_id}->{content};
    }

    $bodies->{cached_until}        = $data->{cachedUntil};
    $bodies->{missing_message_ids} = $data->{result}->{missingMessageIDs};

    return $bodies;
}

=head2 mail_lists

  my $mail_lists = $eapi->mail_lists( character_id  => $character_id );

Returns a hashref with the following structure:

{
    'cached_until' => '2014-07-11 00:06:57',
    '145156367' => 'RAISA Shield Fits'
}

=cut

sub mail_lists {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/mailinglists.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $lists;
    foreach my $list_id ( keys %$result ) {
        $lists->{$list_id} = $result->{$list_id}->{displayName};
    }

    $lists->{cached_until} = $data->{cachedUntil};
  
    return $lists;
}

=head2 starbase_list

  my $starbase_list = $eapi->starbase_list();

=cut

sub starbase_list {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path          => 'corp/StarbaseList.xml.aspx',
        requires_auth => 1,
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $lists;
    foreach my $list_id ( keys %$result ) {
        $lists->{$list_id} = $result->{$list_id};
    }

    $lists->{cached_until} = $data->{cachedUntil};
  
    return $lists;
}


=head2 starbase_detail

  my $starbase_detail = $eapi->starbase_detail( item_id => 111111 );

  Result:

   {
      'fuel' => [
                  {
                    'type_id' => '4247',
                    'quantity' => '7340'
                  },
                  {
                    'type_id' => '16275',
                    'quantity' => '8333'
                  }
                ],
      'combat_settings' => {
                             'on_status_drop_standing' => '0',
                             'on_corporation_war' => '0',
                             'on_aggression' => '0',
                             'on_status_drop_enabled' => '0',
                             'on_standing_drop' => '0',
                             'use_standings_from' => '928827408'
                           },
      'cached_until' => '2016-02-11 18:44:29',
      'general_settings' => {
                              'allow_corporation_members' => '1',
                              'allow_alliance_members' => '1',
                              'usage_flags' => '3',
                              'deploy_flags' => '0'
                            },
      'online_timestamp' => '2015-06-10 07:22:30',
      'state_timestamp' => '2016-02-11 18:26:43',
      'state' => '4'
    }

=cut

sub starbase_detail {
    my ($self, %args) = @_;

    my $item_id = $args{item_id};
    croak('No item_id specified') unless $item_id;

    my $data = $self->_load_xml(
        path          => 'corp/StarbaseDetail.xml.aspx',
        requires_auth => 1,
        item_id       => $item_id,
    );

    my $result = $data->{result};

    return $self->_get_error( $data ) if defined $data->{error};

    my $details;

    $details = {
        state            => $result->{state},
        state_timestamp  => $result->{stateTimestamp},
        online_timestamp => $result->{onlineTimestamp},
        general_settings => {
            usage_flags  => $result->{generalSettings}->{usageFlags},
            deploy_flags => $result->{generalSettings}->{deployFlags},
            allow_corporation_members => $result->{generalSettings}->{allowCorporationMembers},
            allow_alliance_members    => $result->{generalSettings}->{allowAllianceMembers},
        },
        combat_settings => {
            use_standings_from => $result->{combatSettings}->{useStandingsFrom}->{ownerID},
            on_standing_drop => $result->{combatSettings}->{onStandingDrop}->{standing},
            on_status_drop_enabled => $result->{combatSettings}->{onStatusDrop}->{enabled},
            on_status_drop_standing => $result->{combatSettings}->{onStatusDrop}->{standing},
            on_aggression => $result->{combatSettings}->{onAggression}->{enabled},
            on_corporation_war => $result->{combatSettings}->{onCorporationWar}->{enabled},
        },
        fuel => [],
    };

    foreach my $fuel ( keys %{ $result->{rowset}->{row} } ) {
        push @{ $details->{fuel} }, 
            { type_id  => $fuel, 
              quantity => $result->{rowset}->{row}->{$fuel}->{quantity} };
    }


    $details->{cached_until} = $data->{cachedUntil};
  
    return $details;
}

=head2 contracts

  my $contracts = $eapi->contracts( character_id  => $character_id, contract_id => 12345 );
  
  contract_id is optional

Returns a hashref with the following structure:
    {
        'cached_until' => '2014-12-02 15:01:44',
        '87227770' => {
          'date_completed' => '2014-11-02 19:23:40',
          'start_station_id' => '60001039',
          'issuer_id' => '90922771',
          'status' => 'Completed',
          'contract_id' => '87227770',
          'num_days' => '14',
          'availability' => 'Private',
          'buyout' => '0.00',
          'date_accepted' => '2014-11-02 18:56:38',
          'for_corp' => '0',
          'collateral' => '0.00',
          'date_expired' => '2014-11-16 18:31:19',
          'reward' => '0.00',
          'volume' => '60472.7325',
          'issue_corp_id' => '928827408',
          'assignee_id' => '899660590',
          'end_station_id' => '60003043',
          'date_issued' => '2014-11-02 18:31:19',
          'price' => '0.00',
          'type' => 'Courier',
          'title' => '',
          'acceptor_id' => '899660590'
        }
    }

=cut

sub contracts {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/Contracts.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
        contract_id   => $args{contract_id},
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $contracts;

    foreach my $c_id ( keys %$result ) {
        $contracts->{$c_id} = {
            contract_id => $c_id,
            issuer_id   => $result->{$c_id}->{issuerID},
            issue_corp_id => $result->{$c_id}->{issuerCorpID},
            assignee_id   => $result->{$c_id}->{assigneeID},
            acceptor_id   => $result->{$c_id}->{acceptorID},
            start_station_id => $result->{$c_id}->{startStationID},
            end_station_id   => $result->{$c_id}->{endStationID},
            type => $result->{$c_id}->{type},
            status => $result->{$c_id}->{status},
            title   => $result->{$c_id}->{title},
            for_corp => $result->{$c_id}->{forCorp},
            availability => $result->{$c_id}->{availability},
            date_issued  => $result->{$c_id}->{dateIssued},
            date_expired => $result->{$c_id}->{dateExpired},
            date_accepted => $result->{$c_id}->{dateAccepted},
            num_days => $result->{$c_id}->{numDays},
            date_completed => $result->{$c_id}->{dateCompleted},
            price => $result->{$c_id}->{price},
            reward => $result->{$c_id}->{reward},
            collateral => $result->{$c_id}->{collateral},
            buyout => $result->{$c_id}->{buyout},
            volume => $result->{$c_id}->{volume},
        }
    }

    $contracts->{cached_until} = $data->{cachedUntil};
  
    return $contracts;

}

=head2 contract_items

  my $contract_items = $eapi->contract_items( character_id  => $character_id, contract_id => 12345 );
  
  contract_id is necessary

Returns a hashref with the following structure:
{
  'cached_until' => '2024-11-29 14:54:02',
  '87229270' => [
                  {
                    'type_id' => '3082',
                    'included' => '1',
                    'quantity' => '1',
                    'raw_quantity' => undef,
                    'record_id' => '1457473349',
                    'singleton' => '0'
                  },
                  {
                    'type_id' => '3082',
                    'included' => '1',
                    'quantity' => '1',
                    'raw_quantity' => undef,
                    'record_id' => '1457473343',
                    'singleton' => '0'
                  },
                ]
}

=cut

sub contract_items {
    my ($self, %args) = @_;

    my $character_id = $args{character_id} || $self->character_id();
    croak('No character_id or contract_id specified') unless $character_id && $args{contract_id};

    my $contract_id = $args{contract_id};

    my $data = $self->_load_xml(
        path          => 'char/ContractItems.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
        contract_id   => $contract_id,
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $contract;

    foreach my $r_id ( keys %$result ) {
        push @{$contract->{$contract_id}}, {
            record_id    => $r_id,
            type_id      => $result->{$r_id}->{typeID},
            quantity     => $result->{$r_id}->{quantity},
            raw_quantity => $result->{$r_id}->{rawQuantity},
            singleton    => $result->{$r_id}->{singleton},
            included     => $result->{$r_id}->{included},
        }
    }

    $contract->{cached_until} = $data->{cachedUntil};

    return $contract;
}


=head2 character_name

  my $character_name = $eapi->character_name( ids => '90922771,94701913' );

Returns a hashref with the following structure:

{
  '94701913' => 'Milolika Muvila',
  'cached_until' => '2014-08-10 20:59:55',
  '90922771' => 'Chips Merkaba'
}

=cut

sub character_name {
    my ($self, %args) = @_;

    croak('No comma separated character ids specified') unless $args{ids};

    my $data = $self->_load_xml(
        path => 'eve/CharacterName.xml.aspx',
        ids  => $args{ids},
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $names;
    foreach my $char_id ( keys %$result ) {
        $names->{$char_id} = $result->{$char_id}->{name};
    }

    $names->{cached_until} = $data->{cachedUntil};
  
    return $names;
}

=head2 character_id

  my $character_id = $eapi->character_id( names => 'Milolika Muvila,Chips Merkaba' );

Returns a hashref with the following structure:

{
  '94701913' => 'Milolika Muvila',
  'cached_until' => '2014-08-10 20:59:55',
  '90922771' => 'Chips Merkaba'
}

=cut

sub character_ids {
    my ($self, %args) = @_;

    croak('No comma separated character names specified') unless $args{names};

    my $data = $self->_load_xml(
        path  => 'eve/CharacterID.xml.aspx',
        names => $args{names},
    );

    my $result = $data->{result}->{rowset}->{row};

    return $self->_get_error( $data ) if defined $data->{error};

    my $ids;
    foreach my $char_id ( keys %$result ) {
        $ids->{$char_id} = $result->{$char_id}->{name};
    }

    $ids->{cached_until} = $data->{cachedUntil};
  
    return $ids;
}

=head2 station_list

  my $station_list = $eapi->station_list();

Returns a hashref with the following structure:

{
  '61000051' => {
    'station_type_id' => '21644',
    'corporation_name' => 'Nulli Secunda Holding',
    'corporation_id' => '1463841432',
    'station_name' => 'DB1R-4 VIII - We brought the Trash Out',
    'solar_system_id' => '30004470',
    'station_id' => '61000051'
  },
  '61000438' => {
    'station_type_id' => '21646',
    'corporation_name' => 'Greater Western Co-Prosperity Sphere Exec',
    'corporation_id' => '98237912',
    'station_name' => 'F-D49D III - Error - Clever name not found',
    'solar_system_id' => '30000279',
    'station_id' => '61000438'
  }
}

=cut

sub station_list {
    my ($self) = @_;

    my $data = $self->_load_xml(
        path => 'eve/ConquerableStationList.xml.aspx',
    );

    return $self->_get_error( $data ) if defined $data->{error};

    my $stations = {};

    my $rows = $data->{result}->{rowset}->{row};
    foreach my $station_id (keys %$rows) {
        $stations->{$station_id} = {
            station_id       => $station_id,
            station_name     => $rows->{$station_id}->{stationName},
            station_type_id  => $rows->{$station_id}->{stationTypeID},
            solar_system_id  => $rows->{$station_id}->{solarSystemID},
            corporation_id   => $rows->{$station_id}->{corporationID},
            corporation_name => $rows->{$station_id}->{corporationName},
        }; 
    }

    $stations->{cached_until} = $data->{cachedUntil};

    return $stations;

}

=head2 corporation_sheet

  my $station_list = $eapi->corporation_sheet();

Returns a hashref with the following structure:

{
    'shares' => '1000',
    'faction_id' => '0',
    'cached_until' => '2014-08-24 22:18:02',
    'member_count' => '43',
    'alliance_id' => '0',
    'corporation_id' => '1043735888',
    'description' => "\x{418}\x{441}\x{441}\x{43b}\x{435}\x{434}\x{43e}\x{432}\x{430}\x{43d}\x{438}\x{44f} \x{438} \x{440}\x{430}\x{437}\x{440}\x{430}\x{431}\x{43e}\x{442}\x{43a}\x{438}",
    'station_id' => '60004861',
    'ceo_name' => 'Krasotulya',
    'logo' => {
                'color3' => '674',
                'color1' => '677',
                'shape3' => '415',
                'shape2' => '480',
                'graphic_id' => '0',
                'shape1' => '437',
                'color2' => '676'
              },
    'tax_rate' => '5',
    'corporation_name' => 'Zaporozhye Sich',
    'ceo_id' => '423270919',
    'url' => 'http://',
    'station_name' => 'Lasleinur V - Moon 11 - Republic Fleet Assembly Plant'
}

=cut

sub corporation_sheet {
    my ($self, %args) = @_;

    croak('No corporation_id specified') unless $args{corporation_id};

    my $data = $self->_load_xml(
        path            => 'corp/CorporationSheet.xml.aspx',
        requires_auth => 1,
        corporation_id  => $args{corporation_id},
    );

    return $self->_get_error( $data ) if defined $data->{error};

    my $corp_info = {};

    my $result = $data->{result};
    
    $corp_info->{cached_until}      = $data->{cachedUntil};
    $corp_info->{corporation_id}    = $result->{corporationID};
    $corp_info->{corporation_name}  = $result->{corporationName};
    $corp_info->{ticker}            = $result->{ticker};
    $corp_info->{ceo_id}            = $result->{ceoID};
    $corp_info->{ceo_name}          = $result->{ceoName};
    $corp_info->{station_id}        = $result->{stationID};
    $corp_info->{station_name}      = $result->{stationName};
    $corp_info->{description}       = $result->{description};
    $corp_info->{url}               = $result->{url};
    $corp_info->{alliance_id}       = $result->{allianceID};
    $corp_info->{faction_id}        = $result->{factionID};
    $corp_info->{tax_rate}          = $result->{taxRate};
    $corp_info->{member_count}      = $result->{memberCount};
    $corp_info->{shares}            = $result->{shares};
    $corp_info->{logo}->{graphic_id}  = $result->{logo}->{graphicID};
    $corp_info->{logo}->{shape1}      = $result->{logo}->{shape1};
    $corp_info->{logo}->{shape2}      = $result->{logo}->{shape2};
    $corp_info->{logo}->{shape3}      = $result->{logo}->{shape3};
    $corp_info->{logo}->{color1}      = $result->{logo}->{color1};
    $corp_info->{logo}->{color2}      = $result->{logo}->{color2};
    $corp_info->{logo}->{color3}      = $result->{logo}->{color3};

    return $corp_info;
}

# Generate error answer
sub _get_error {
    my ($self, $data) = @_;

    return {
        error => $data->{error} || { code => 500, content => 'Unknown error' },
    };
}

# convert keys
sub _parse_assets {
    my ($self, $xml) = @_;

    return () unless $xml;

    my $parsed;
    my $rows = $xml->{rowset}->{row};

    foreach my $id ( keys %$rows ) {
        $parsed->{$id}->{item_id}      = $id;
        $parsed->{$id}->{location_id}  = $rows->{$id}->{locationID} if $rows->{$id}->{locationID};
        $parsed->{$id}->{raw_quantity} = $rows->{$id}->{rawQuantity};
        $parsed->{$id}->{quantity}     = $rows->{$id}->{quantity};
        $parsed->{$id}->{flag}         = $rows->{$id}->{flag};
        $parsed->{$id}->{singleton}    = $rows->{$id}->{singleton};
        $parsed->{$id}->{type_id}      = $rows->{$id}->{typeID};

        if ( $rows->{$id}->{rowset} && $rows->{$id}->{rowset}->{name} eq 'contents' ) {
            $parsed->{$id}->{contents} = $self->_parse_assets( $rows->{$id} );
        }
    }

    return $parsed;
}

sub _load_xml {
    my $self = shift;
    my %args = @_;

    my $xml = $self->_retrieve_xml( @_ );

    my $data = $self->_parse_xml( $xml, $args{path} );

    if ( $args{path} ne 'eve/SkillTree.xml.aspx' ) {
      die('Unsupported EveOnline API XML version (requires version 2)') if ($data->{version} != 2);
    }
    return $data;
}

sub _retrieve_xml {
    my ($self, %args) = @_;

    croak('No feed path provided') if !$args{path};

    my $params = {};

    if ($args{requires_auth}) {
        $params->{keyID} = $self->user_id();
        $params->{vCode} = $self->api_key();
    }

    if ($args{character_id}) {
        $params->{characterID} = $args{character_id};
    }
    if ($args{row_count}) {
        $params->{rowCount}    = $args{row_count};
    }
    if ($args{account_key}) {
        $params->{accountKey}  = $args{account_key};
    }
    if ($args{from_id}) {
        $params->{fromID}      = $args{from_id};
    }
    if ($args{ids}) {
        $params->{ids}         = $args{ids};
    }
    if ($args{names}) {
        $params->{names}       = $args{names};
    }
    if ($args{corporation_id}) {
        $params->{corporationID} = $args{corporation_id};
    }
    if ($args{contract_id}) {
        $params->{contractID} = $args{contract_id};
    }
    if ($args{item_id}) {
        $params->{itemID} = $args{item_id};
    }
    if ($args{job_id}) {
        $params->{jobID} = $args{job_id};
    }

    my $uri = URI->new( $self->api_url() . '/' . $args{path} );
    $uri->query_form( $params );

    my $ua = LWP::UserAgent->new;
    my $xml = $ua->get( $uri->as_string() );

    return $xml->content;
}

sub _parse_xml {
    my ($self, $xml, $path) = @_;

    my $data;
    # XML::Simple is not recomended for parse XML cause combined attrs like jumpCloneID and typeID 
    # in response for char/CharacterSheet (node jumpCloneImplants) are croped
    # TODO: XML::Simple -> XML::LibXML or delete KeyAttr parameters and refactor all code and tests
    my $key_attr = ['jobID', 'characterID', 'listID', 'messageID', 'transactionID', 'refID', 'itemID', 'jumpCloneID', 'typeID', 'stationID', 'bonusType', 'groupID', 'refTypeID', 'solarSystemID', 'name', 'contactID', 'contractID'];

    if ( $path eq 'char/ContractItems.xml.aspx' ) {
      # One more reason to kill XML::Simple
      $key_attr = ['characterID', 'listID', 'messageID', 'transactionID', 'refID', 'itemID', 'jumpCloneID', 'recordID', 'typeID', 'stationID', 'bonusType', 'groupID', 'refTypeID',  'jobID', 'solarSystemID', 'name', 'contactID', 'contractID'];
    }
    
    if ( $path eq 'eve/SkillTree.xml.aspx' ) {
        # For https://github.com/bluefeet/Games-EveOnline-API/issues/5
        # TODO: rewrite to XML::LibXML all methods
        $data = XML::LibXML->load_xml( string => $xml ); 
    }
    else {
      $data = XML::Simple::XMLin(
          $xml,
          ForceArray => ['row'],
          KeyAttr    => $key_attr,
      );
    }

    return $data;
}

1;
__END__

=head1 SEE ALSO

=over

=item *

L<WebService::EveOnline>

=back

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 CONTRIBUTORS

=over

=item *

Andrey Chips Kuzmin <chipsoid@cpan.org>

=back

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


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
use LWP::Simple qw();
use XML::Simple qw();
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

    my $group_rows = $data->{result}->{rowset}->{row};
    foreach my $group_id (keys %$group_rows) {
        my $group_result = $result->{$group_id} ||= {};
        $group_result->{name} = $group_rows->{$group_id}->{groupName};

        $group_result->{skills} = {};
        my $skill_rows = $group_rows->{$group_id}->{rowset}->{row};
        foreach my $skill_id (keys %$skill_rows) {
            my $skill_result = $group_result->{skills}->{$skill_id} ||= {};
            $skill_result->{name}                = $skill_rows->{$skill_id}->{typeName};
            $skill_result->{description}         = $skill_rows->{$skill_id}->{description};
            $skill_result->{rank}                = $skill_rows->{$skill_id}->{rank};
            $skill_result->{primary_attribute}   = $skill_rows->{$skill_id}->{requiredAttributes}->{primaryAttribute};
            $skill_result->{secondary_attribute} = $skill_rows->{$skill_id}->{requiredAttributes}->{secondaryAttribute};

            $skill_result->{bonuses} = {};
            my $bonus_rows = $skill_rows->{$skill_id}->{rowset}->{skillBonusCollection}->{row};
            foreach my $bonus_name (keys %$bonus_rows) {
                $skill_result->{bonuses}->{$bonus_name} = $bonus_rows->{$bonus_name}->{bonusValue};
            }

            $skill_result->{required_skills} = {};
            my $required_skill_rows = $skill_rows->{$skill_id}->{rowset}->{requiredSkills}->{row};
            foreach my $required_skill_id (keys %$required_skill_rows) {
                $skill_result->{required_skills}->{$required_skill_id} = $required_skill_rows->{$required_skill_id}->{skillLevel};
            }
        }
    }

    $result->{cached_until} = $data->{cachedUntil};

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
    my $result = $data->{result};

    my $sheet         = {};
    my $enhancers     = $sheet->{attribute_enhancers} = {};
    my $enhancer_rows = $result->{attributeEnhancers};
    foreach my $attribute (keys %$enhancer_rows) {
        my ($real_attribute) = ($attribute =~ /^([a-z]+)/xm);
        my $enhancer         = $enhancers->{$real_attribute} = {};

        $enhancer->{name}  = $enhancer_rows->{$attribute}->{augmentatorName};
        $enhancer->{value} = $enhancer_rows->{$attribute}->{augmentatorValue};
    }

    $sheet->{blood_line}       = $result->{bloodLine};
    $sheet->{name}             = $result->{name};
    $sheet->{corporation_id}   = $result->{corporationID};
    $sheet->{corporation_name} = $result->{corporationName};
    $sheet->{balance}          = $result->{balance};
    $sheet->{race}             = $result->{race};
    $sheet->{attributes}       = $result->{attributes};

    my $skills     = $sheet->{skills} = {};
    my $skill_rows = $result->{rowset}->{row};
    foreach my $skill_id (keys %$skill_rows) {
        my $skill = $skills->{$skill_id} = {};

        $skill->{level}        = $skill_rows->{$skill_id}->{level};
        $skill->{skill_points} = $skill_rows->{$skill_id}->{skillpoints};
    }

    $sheet->{cached_until} = $data->{cachedUntil};

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

    return()  unless $result->{skillInTraining};

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

    return() unless $result->{type};

    my $key_info = {
        type    => $result->{type},
        expires => $result->{expires},
        access_mask => $result->{accessMask},
    };

    # TODO: add structure for corporation and alliance API
    if ( defined $result->{rowset}->{row} && $result->{type} eq 'Account' ) {
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

    return() unless $result->{createDate};

    return {
        paid_until    => $result->{paidUntil},
        create_date   => $result->{createDate},
        logon_count   => $result->{logonCount},
        logon_minutes => $result->{logonMinutes},
        cachedUntil   => $data->{cachedUntil},
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

    return() unless $result->{characterID};

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
        foreach my $history_row ( @{$result->{rowset}->{row}} ) {
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

    return() unless $result->{rowset}->{row};

    return $self->_parse_assets( $result );
}

=head2 contact_list

  my $contact_list = $eapi->contact_list();

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
    croak('No character_id specified') unless $character_id;

    my $data = $self->_load_xml(
        path          => 'char/ContactList.xml.aspx',
        requires_auth => 1,
        character_id  => $character_id,
    );

    my $result = $data->{result};

    return() unless $result->{rowset};

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

    return $contacts;
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

    my $xml = $self->_retrieve_xml( @_ );

    my $data = $self->_parse_xml( $xml );
    die('Unsupported EveOnline API XML version (requires version 2)') if ($data->{version} != 2);

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

    my $uri = URI->new( $self->api_url() . '/' . $args{path} );
    $uri->query_form( $params );

    my $xml = LWP::Simple::get( $uri->as_string() );

    return $xml;
}

sub _parse_xml {
    my ($self, $xml) = @_;

    my $data = XML::Simple::XMLin(
        $xml,
        ForceArray => ['row'],
        KeyAttr    => ['characterID', 'itemID', 'typeID', 'bonusType', 'groupID', 'refTypeID', 'solarSystemID', 'name', 'contactID'],
    );

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


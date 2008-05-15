package Games::EveOnline::API;

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
  my $sheet = $eapi->character_sheet( $character_id );
  my $in_training = $eapi->skill_in_training( $character_id );

=head1 DESCRIPTION

This module provides a Perl wrapper around the Eve-Online API, version 2.
The need for the wrapper arrises for two reasons.  First, the XML that
is provided by the API is overly complex, at least for my taste.  So, other
than just returning you a perl data representation of the XML, it also
simplifies the results.

Second, I want to write a L<DBIx::Class> wrapper around the API, and it
made more sense to first create a low-level perl interface to the API,
and then use it to power the higher level DBIC API.

Only a couple of the methods provided by this module can be used straight
away.  The rest require that you get a user_id and api_key.  You can get
these at:

L<http://myeve.eve-online.com/api/default.asp>

Also, this modules does not attempt to duplicate the documentation already
provided by CCP.  Read their API docs too:

L<http://myeve.eve-online.com/api/doc/>

=cut

use Moose;

use URI;
use LWP::Simple qw();
use XML::Simple qw();

=head1 ATTRIBUTES

=head2 user_id

=head2 api_key

=head2 api_url

=cut

has 'user_id'   => (is=>'rw', isa=>'Int',     default=>0 );
has 'api_key'   => (is=>'rw', isa=>'Str',     default=>'' );
has 'api_url'   => (is=>'rw', isa=>'Str',     default=>'http://api.eve-online.com');

=head1 METHODS

Most of these methods return a 'cached_until' value.  I've no clue if this
is CCP telling you how long you should cache the information before you
should request it again, or if this is the point at which CCP will refresh
their cache of this information.

Either way, it is good etiquet to follow the cacheing guidelines of a
provider.  If you over-use the API I'm sure you'll eventually get blocked.

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

    my $data = $self->load_xml(
        'eve/SkillTree.xml.aspx',
        no_auth => 1,
    );

    my $result;

    my $group_rows = $data->{rowset}->{row};
    foreach my $group_id (keys %$group_rows) {
        my $group_result = $result->{$group_id} ||= {};
        $group_result->{name} = $group_rows->{$group_id}->{groupName};

        $group_result->{skills} = {};
        my $skill_rows = $group_rows->{$group_id}->{rowset}->{row};
        foreach my $skill_id (keys %$skill_rows) {
            my $skill_result = $group_result->{skills}->{$skill_id} ||= {};
            $skill_result->{name} = $skill_rows->{$skill_id}->{typeName};
            $skill_result->{description} = $skill_rows->{$skill_id}->{description};
            $skill_result->{rank} = $skill_rows->{$skill_id}->{rank};
            $skill_result->{primary_attribute} = $skill_rows->{$skill_id}->{requiredAttributes}->{primaryAttribute};
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

    $result->{cached_until} = $data->{cached_until};

    return $result;
}

=head2 ref_types

  my $ref_types = $eapi->ref_types();

Returns all a simple hash structure of types of financial
activity.  This is useful when pulling wallet information.
The key of the has is the ref type's ID, and the value of
the title of the ref type.

=cut

sub ref_types {
    my ($self) = @_;

    my $data = $self->load_xml(
        'eve/RefTypes.xml.aspx',
        no_auth => 1,
    );

    my $ref_types = {};

    my $rows = $data->{rowset}->{row};
    foreach my $ref_type_id (keys %$rows) {
        $ref_types->{$ref_type_id} = $rows->{$ref_type_id}->{refTypeName};
    }

    $ref_types->{cached_until} = $data->{cached_until};

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

    my $data = $self->load_xml(
        'map/Sovereignty.xml.aspx',
        no_auth => 1,
    );
    my $result = $data->{result};

    my $systems = {};

    my $rows = $result->{rowset}->{row};
    foreach my $system_id (keys %$rows) {
        my $system = $systems->{$system_id} = {};
        $system->{name} = $rows->{$system_id}->{solarSystemName};
        $system->{faction_id} = $rows->{$system_id}->{factionID};
        $system->{sovereignty_level} = $rows->{$system_id}->{sovereigntyLevel};
        $system->{constellation_sovereignty} = $rows->{$system_id}->{constellationSovereignty};
        $system->{alliance_id} = $rows->{$system_id}->{allianceID};
    }

    $systems->{cached_until} = $data->{cached_until};
    $systems->{data_time}    = $data->{data_time};

    return $systems;
}

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

    my $data = $self->load_xml(
        'account/Characters.xml.aspx',
    );
    my $result = $data->{result};

    my $characters = {};
    my $rows = $result->{rowset}->{row};

    foreach my $character_id (keys %$rows) {
        $characters->{$character_id} = {
            name             => $rows->{$character_id}->{name},
            corporation_name => $rows->{$character_id}->{corporationName},
            corporation_id   => $rows->{$character_id}->{corporationID},
        };
    }

    $characters->{cache_until} = $data->{cacheUntil};

    return $characters;
}

=head2 character_sheet

  my $sheet = $eapi->character_sheet( $character_id );

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
    my ($self, $character_id) = @_;

    my $data = $self->load_xml(
        'char/CharacterSheet.xml.aspx',
        params => { characterID => $character_id },
    );
    my $result = $data->{result};

    my $sheet         = {};
    my $enhancers     = $sheet->{attribute_enhancers} = {};
    my $enhancer_rows = $result->{attributeEnhancers};
    foreach my $attribute (keys %$enhancer_rows) {
        my ($real_attribute) = ($attribute =~ /^([a-z]+)/);
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

    $sheet->{cache_until} = $data->{cacheUntil};

    return $sheet;
}

=head2 skill_in_training

  my $in_training = $eapi->skill_in_training( $character_id );

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
    my ($self, $character_id) = @_;

    my $data = $self->load_xml(
        'char/SkillInTraining.xml.aspx',
        params => { characterID => $character_id },
    );
    my $result = $data->{result};

    return() if (!$result->{skillInTraining});

    my $training = {
        current_tq_time => $result->{currentTQTime},
        skill_id => $result->{trainingTypeID},
        to_level => $result->{trainingToLevel},
        start_time => $result->{trainingStartTime},
        end_time => $result->{trainingEndTime},
        start_sp => $result->{trainingStartSP},
        end_sp => $result->{trainingDestinationSP},
    };

    $training->{cache_until} = $data->{cacheUntil};

    return $training;
}

=head2 load_xml

  my $data = $eapi->load_xml(
    'some/FeedSource.xml.aspx',
    no_auth => 1,       # Whether to pass the user_id and api_key.
    params  => { ... }, # Any extra params.
  );

Calls the specified URL (prepended with the api_url), passes any
parameters, and parses the resulting XML in to a perl complex
data structure.

Normally you will not want to use this directly, as all of the
available Eve APIs are implemented in this module.

=cut

sub load_xml {
    my ($self, $path, %args) = @_;

    my $params = $args{params} || {};
    if (!$args{no_auth}) {
        $params->{userID} ||= $self->user_id();
        $params->{apiKey} ||= $self->api_key();
    }

    my $uri = URI->new( $self->api_url() . '/' . $path );
    $uri->query_form( %$params );

    my $xml = LWP::Simple::get( $uri->as_string() );
    my $data = XML::Simple::XMLin(
        $xml,
        ForceArray => ['row'],
        KeyAttr    => ['characterID', 'typeID', 'bonusType', 'groupID', 'refTypeID', 'solarSystemID', 'name'],
    );
    die('Unsupported EveOnline API XML version (requires version 2)') if ($data->{version} != 2);

    return $data;
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@cpan.org>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


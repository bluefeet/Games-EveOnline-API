package Games::EveOnline::API;

use Moose;

use URI;
use LWP::Simple qw();
use XML::Simple qw();

has 'api_url' => (is=>'rw', isa=>'Str', default=>'http://api.eve-online.com');
has 'user_id' => (is=>'rw', isa=>'Int', default=>0 );
has 'api_key' => (is=>'rw', isa=>'Str', default=>'' );

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

    return $result;
}

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

    return $ref_types;
}

sub sovereignty {
    my ($self) = @_;

    my $data = $self->load_xml(
        'map/Sovereignty.xml.aspx',
        no_auth => 1,
    );

    my $systems = {};

    my $rows = $data->{rowset}->{row};
    foreach my $system_id (keys %$rows) {
        my $system = $systems->{$system_id} = {};
        $system->{name} = $rows->{$system_id}->{solarSystemName};
        $system->{faction_id} = $rows->{$system_id}->{factionID};
        $system->{sovereignty_level} = $rows->{$system_id}->{sovereigntyLevel};
        $system->{constellation_sovereignty} = $rows->{$system_id}->{constellationSovereignty};
        $system->{alliance_id} = $rows->{$system_id}->{allianceID};
    }

    return $systems;
}

sub characters {
    my ($self) = @_;

    my $data = $self->load_xml(
        'account/Characters.xml.aspx',
    );

    my $characters = {};
    my $rows = $data->{rowset}->{row};

    foreach my $character_id (keys %$rows) {
        $characters->{$character_id} = {
            id               => $character_id,
            name             => $rows->{$character_id}->{name},
            corporation_name => $rows->{$character_id}->{corporationName},
            corporation_id   => $rows->{$character_id}->{corporationID},
        };
    }

    return $characters;
}

sub character_sheet {
    my ($self, $character_id) = @_;

    my $data = $self->load_xml(
        'char/CharacterSheet.xml.aspx',
        params => { characterID => $character_id },
    );

    my $sheet = {};
    my $enhancers = $sheet->{attribute_enhancers} = {};
    my $enhancer_rows = $data->{attributeEnhancers};
    foreach my $attribute (keys %$enhancer_rows) {
        my ($real_attribute) = ($attribute =~ /^([a-z]+)/);
        my $enhancer = $enhancers->{$real_attribute} = {};
        $enhancer->{name} = $enhancer_rows->{$attribute}->{augmentatorName};
        $enhancer->{value} = $enhancer_rows->{$attribute}->{augmentatorValue};
    }

    $sheet->{blood_line} = $data->{bloodLine};
    $sheet->{name} = $data->{name};
    $sheet->{corporation_id} = $data->{corporationID};
    $sheet->{corporation_name} = $data->{corporationName};
    $sheet->{balance} = $data->{balance};
    $sheet->{race} = $data->{race};
    $sheet->{attributes} = $data->{attributes};

    my $skills = $sheet->{skills} = {};
    my $skill_rows = $data->{rowset}->{row};
    foreach my $skill_id (keys %$skill_rows) {
        my $skill = $skills->{$skill_id} = {};
        $skill->{level} = $skill_rows->{$skill_id}->{level};
        $skill->{skill_points} = $skill_rows->{$skill_id}->{skillpoints};
    }

    return $sheet;
}

sub skill_in_training {
    my ($self, $character_id) = @_;

    my $data = $self->load_xml(
        'char/SkillInTraining.xml.aspx',
        params => { characterID => $character_id },
    );

    return() if (!$data->{skillInTraining});

    my $result = {
        current_tq_time => $data->{currentTQTime},
        skill_id => $data->{trainingTypeID},
        to_level => $data->{trainingToLevel},
        start_time => $data->{trainingStartTime},
        end_time => $data->{trainingEndTime},
        start_sp => $data->{trainingStartSP},
        end_sp => $data->{trainingDestinationSP},
    };

    return $result;
}

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

    $data->{result}->{xml} = $xml;
    return $data->{result};
}

1;

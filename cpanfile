requires 'Moo' => '1.004005';
requires 'Type::Tiny' => '0.044';
requires 'LWP::UserAgent';
requires 'XML::Simple';
requires 'URI';

on test => sub {
    requires 'Test::Simple' => '0.94';
};

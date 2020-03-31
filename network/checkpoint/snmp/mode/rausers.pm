#
# Copyright 2020 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package network::checkpoint::snmp::mode::rausers;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold catalog_status_calc);

sub custom_status_output {
    my ($self, %options) = @_;

    return 'status : ' . $self->{result_values}->{status};
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => 0 },
        { name => 'ratunnel', type => 1, cb_prefix_output => 'prefix_vpn_output', message_multiple => 'All Remote Remote Access users tunnel are OK' }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'rausers-total', nlabel => 'ra.users.total.count', display_ok => 0, set => {
                key_values => [ { name => 'total' } ],
                output_template => 'current total number of Remote Acess users: %d',
                perfdatas => [
                    { value => 'total_absolute', template => '%d', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{ratunnel} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'type' }, { name => 'status' }, { name => 'display' } ],
                closure_custom_calc => \&catalog_status_calc,
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, force_new_perfdata => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => { 
        'filter-ip:s'       => { name => 'filter_ip' },
        'warning-status:s'  => { name => 'warning_status', default => '' },
        'critical-status:s' => { name => 'critical_status', default => '%{type} eq "permanent" and %{status} =~ /down/i' },
        'filter-name:s'     => { name => 'filter_ip' },
        'buggy-snmp'        => { name => 'buggy_snmp' },
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $self->change_macros(macros => ['warning_status', 'critical_status']);
}

sub prefix_vpn_output {
    my ($self, %options) = @_;

    return "RATunnel '" . $options{instance_value}->{display} . "' ";
}

my $map_state = {
    3 => 'active', 4 => 'destroy', 129 => 'idle', 130 => 'phase1',
    131 => 'down', 132 => 'init'
};

my $mapping = {
    raInternalIpAddr   => { oid => '.1.3.6.1.4.1.2620.500.9000.1.1' },
    raExternalIpAddr   => { oid => '.1.3.6.1.4.1.2620.500.9000.1.19' },
    raUserState        => { oid => '.1.3.6.1.4.1.2620.500.9000.1.20', map => $map_state },
};
my $oid_raUsersEntry = '.1.3.6.1.4.1.2620.500.9000';

sub manage_selection {
    my ($self, %options) = @_;

    my $snmp_result;
    if (defined($self->{option_results}->{buggy_snmp})) {
        $snmp_result = $options{snmp}->get_table(oid => $oid_raUsersEntry, nothing_quit => 1);
    } else {
        $snmp_result = $options{snmp}->get_multiple_table(
            oids => [
                { oid => $oid_raUsersEntry }
            ],
            nothing_quit => 1,
            return_type => 1
        );
    }

    $self->{global} = { total => 0 };
    $self->{vs} = {};
    foreach my $oid (keys %{$snmp_result}) {
        next if ($oid !~ /^$mapping->{raUserState}->{oid}\.(.*)$/);
        my $instance = $1;
        my $result = $options{snmp}->map_instance(mapping => $mapping, results => $snmp_result, instance => $instance);

        if (defined($self->{option_results}->{filter_ip}) && $self->{option_results}->{filter_ip} ne '' &&
            $result->{raExternalIpAddr} !~ /$self->{option_results}->{filter_ip}/) {
            $self->{output}->output_add(long_msg => "skipping '" . $result->{raExternalIpAddr} . "': no matching filter.", debug => 1);
            next;
        }

        $self->{ratunnel}->{$instance} = {
            display => $result->{raExternalIpAddr}, 
            status => $result->{raUserState},
        };
        $self->{global}->{total}++;
    }

    if (scalar(keys %{$self->{ratunnel}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No Remote Access user found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check Remote Access users tunnel information

=over 8

=item B<--filter-ip>

Filter ip (can be a regexp).

=item B<--warning-status>

Set warning threshold for status.
Can used special variables like: %{type}, %{status}, %{display}

=item B<--critical-status>

Set critical threshold for status (Default: '%{type} eq "permanent" and %{status} =~ /down/i').
Can used special variables like: %{type}, %{status}, %{display}

=item B<--buggy-snmp>

Checkpoint snmp can be buggy. Test that option if no response.

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'rausers-total'.

=back

=cut

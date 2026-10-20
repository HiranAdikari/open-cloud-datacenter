package config

import (
	"net"
	"strings"
	"testing"
)

// mustCIDR is the external network every case below is validated against.
func mustCIDR(t *testing.T, s string) *net.IPNet {
	t.Helper()
	_, n, err := net.ParseCIDR(s)
	if err != nil {
		t.Fatalf("bad test CIDR %q: %v", s, err)
	}
	return n
}

// TestValidateReservedEntry covers DCAPI_VPC_EXTERNAL_RESERVED_IPS entries.
// Ranges matter on lk-dev: dc-api's ovn-vpc-external-network shares VLAN 702
// with a subnet owned by another team, so dc-api must exclude that subnet's
// half of the /25 and a single-IP-only parser would need 62 entries.
func TestValidateReservedEntry(t *testing.T) {
	extNet := mustCIDR(t, "172.22.101.0/25")

	cases := []struct {
		name    string
		entry   string
		wantErr string // substring; "" means expect success
	}{
		{"single IP inside", "172.22.101.6", ""},
		{"gateway itself", "172.22.101.126", ""},
		{"range inside", "172.22.101.2..172.22.101.63", ""},
		{"range single-width", "172.22.101.9..172.22.101.9", ""},
		{"range spanning whole subnet", "172.22.101.0..172.22.101.127", ""},
		{"range with spaces", " 172.22.101.2 .. 172.22.101.63 ", ""},

		{"single IP outside", "192.168.1.5", "not inside"},
		{"garbage", "not-an-ip", "invalid IP"},
		{"range low bound outside", "172.22.100.1..172.22.101.63", "not inside"},
		{"range high bound outside", "172.22.101.2..172.22.102.9", "not inside"},
		{"range reversed", "172.22.101.63..172.22.101.2", "reversed"},
		{"range malformed high", "172.22.101.2..nope", "not a valid"},
		{"range malformed low", "nope..172.22.101.63", "not a valid"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateReservedEntry(strings.TrimSpace(tc.entry), extNet)
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("want success, got %v", err)
				}
				return
			}
			if err == nil {
				t.Fatalf("want error containing %q, got nil", tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("want error containing %q, got %q", tc.wantErr, err.Error())
			}
		})
	}
}

// TestValidateF15_LkDevSharedVlan is the exact lk-dev configuration: dc-api
// takes 172.22.101.64-.125 while the other team's subnetexternal keeps .2-.63.
func TestValidateF15_LkDevSharedVlan(t *testing.T) {
	c := &Config{
		VPCExternalCIDR:    "172.22.101.0/25",
		VPCExternalGateway: "172.22.101.126",
		VPCExternalReservedIPs: strings.Join([]string{
			"172.22.101.1",
			"172.22.101.2..172.22.101.63",
			"172.22.101.127",
		}, ","),
	}
	if err := c.ValidateF15(); err != nil {
		t.Fatalf("lk-dev shared-VLAN config must validate, got: %v", err)
	}
}

// TestValidateF15_RejectsBadRange proves a typo'd range is fatal at config
// load rather than silently excluding nothing and letting KubeOVN's IPAM hand
// out addresses that belong to the other team's subnet.
func TestValidateF15_RejectsBadRange(t *testing.T) {
	c := &Config{
		VPCExternalCIDR:        "172.22.101.0/25",
		VPCExternalGateway:     "172.22.101.126",
		VPCExternalReservedIPs: "172.22.101.63..172.22.101.2",
	}
	err := c.ValidateF15()
	if err == nil {
		t.Fatal("reversed range must be rejected")
	}
	if !strings.Contains(err.Error(), "reversed") {
		t.Fatalf("want a 'reversed' error, got %q", err.Error())
	}
}

// TestParseReservedIPs_NormalisesRangeBounds pins the fix for a bug that
// validation alone could not catch: ValidateF15 trims the halves of a range
// before parsing them, so " 10.0.0.2 .. 10.0.0.9 " validates cleanly — but the
// entry is then handed to KubeOVN's Subnet excludeIps verbatim, and its
// ExpandExcludeIPs splits on ".." WITHOUT trimming. The bounds arrive as
// "10.0.0.2 " and " 10.0.0.9", neither parses as an IP, and the range silently
// excludes nothing. ParseReservedIPs must emit the normalised form.
func TestParseReservedIPs_NormalisesRangeBounds(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []string
	}{
		{"spaces around range bounds", "172.22.101.2 .. 172.22.101.63", []string{"172.22.101.2..172.22.101.63"}},
		{"spaces around entry and bounds", "  172.22.101.2  ..  172.22.101.63  ", []string{"172.22.101.2..172.22.101.63"}},
		{"already tight", "172.22.101.2..172.22.101.63", []string{"172.22.101.2..172.22.101.63"}},
		{"single IPs untouched", "10.0.0.1, 10.0.0.2", []string{"10.0.0.1", "10.0.0.2"}},
		{"mixed", "10.0.0.1, 10.0.0.4 .. 10.0.0.9", []string{"10.0.0.1", "10.0.0.4..10.0.0.9"}},
		{"empty entries dropped", "10.0.0.1,,  ,10.0.0.2", []string{"10.0.0.1", "10.0.0.2"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := (&Config{VPCExternalReservedIPs: tc.in}).ParseReservedIPs()
			if len(got) != len(tc.want) {
				t.Fatalf("got %q, want %q", got, tc.want)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Fatalf("entry %d: got %q, want %q (full: %q)", i, got[i], tc.want[i], got)
				}
			}
		})
	}
}

// TestParseReservedIPs_OutputRevalidates guards the round trip: whatever
// ParseReservedIPs emits must still satisfy validateReservedEntry, so a
// normalisation that corrupted an entry would be caught here rather than in a
// cluster.
func TestParseReservedIPs_OutputRevalidates(t *testing.T) {
	extNet := mustCIDR(t, "172.22.101.0/25")
	c := &Config{VPCExternalReservedIPs: " 172.22.101.1 , 172.22.101.2 .. 172.22.101.63 , 172.22.101.127 "}
	for _, e := range c.ParseReservedIPs() {
		if err := validateReservedEntry(e, extNet); err != nil {
			t.Fatalf("entry %q from ParseReservedIPs does not revalidate: %v", e, err)
		}
	}
}

package kubeovn

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	dynamicfake "k8s.io/client-go/dynamic/fake"
)

// Harvester's bundled kubeovn-operator Addon ships its own ProviderNetwork
// bound to a dedicated NIC and its own Vlan per tag. dc-api must bind to those
// rather than create a second ProviderNetwork on the same physical port and a
// second Vlan with the same tag — KubeOVN flags that as a conflict.
//
// These tests pin the adoption behaviour added for lk-dev's move to the add-on.

// newFakeClient returns a Client backed by a fake dynamic client.
//
// Seeded objects are created THROUGH the client against an explicit GVR rather
// than passed to the constructor. The fake client's default pluralizer derives
// the GVR from kind, which yields "providernetworks" for ProviderNetwork while
// the real resource is "provider-networks" — constructor-seeded objects would
// silently land under a resource nothing reads.
func newFakeClient(seed ...seeded) (*Client, *dynamicfake.FakeDynamicClient) {
	listKinds := map[schema.GroupVersionResource]string{
		providerNetworkGVR: "ProviderNetworkList",
		vlanGVR:            "VlanList",
		subnetGVR:          "SubnetList",
		nadGVR:             "NetworkAttachmentDefinitionList",
	}
	dyn := dynamicfake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), listKinds)
	for _, s := range seed {
		ri := dyn.Resource(s.gvr)
		var err error
		if ns := s.obj.GetNamespace(); ns != "" {
			_, err = ri.Namespace(ns).Create(context.Background(), s.obj, metav1.CreateOptions{})
		} else {
			_, err = ri.Create(context.Background(), s.obj, metav1.CreateOptions{})
		}
		if err != nil {
			panic("seeding fake client: " + err.Error())
		}
	}
	return &Client{dynamic: dyn}, dyn
}

type seeded struct {
	gvr schema.GroupVersionResource
	obj *unstructured.Unstructured
}

func unstruct(apiVersion, kind, name string, spec map[string]interface{}) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": apiVersion,
		"kind":       kind,
		"metadata":   map[string]interface{}{"name": name},
		"spec":       spec,
	}}
}

// addonObjects mirrors what Harvester's kubeovn-operator Addon has on lk-dev.
func addonObjects() []seeded {
	return []seeded{
		{providerNetworkGVR, unstruct("kubeovn.io/v1", "ProviderNetwork", "ovnpn",
			map[string]interface{}{"defaultInterface": "eno1np0"})},
		{vlanGVR, unstruct("kubeovn.io/v1", "Vlan", "vlan702",
			map[string]interface{}{"id": int64(702), "provider": "ovnpn"})},
	}
}

func lkDevCfg() ExternalNetworkConfig {
	return ExternalNetworkConfig{
		Bridge:          "vm-network-br",
		CIDR:            "172.22.101.0/25",
		Gateway:         "172.22.101.126",
		VLANID:          702,
		ProviderNetwork: "ovnpn",
		VlanName:        "vlan702",
	}
}

// TestBootstrap_AdoptsAddonObjects: with adoption configured, dc-api must not
// create a ProviderNetwork or Vlan, must leave the add-on's specs untouched,
// and must point its Subnet at the adopted Vlan.
func TestBootstrap_AdoptsAddonObjects(t *testing.T) {
	c, dyn := newFakeClient(addonObjects()...)
	c.WithExternalNetwork(lkDevCfg())

	if err := c.EnsureExternalNetworkBootstrap(context.Background()); err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	pns, err := dyn.Resource(providerNetworkGVR).List(context.Background(), listAll())
	if err != nil {
		t.Fatal(err)
	}
	if len(pns.Items) != 1 {
		var names []string
		for _, i := range pns.Items {
			names = append(names, i.GetName())
		}
		t.Fatalf("want exactly 1 ProviderNetwork (the adopted one), got %d: %v", len(pns.Items), names)
	}
	if got, _, _ := unstructured.NestedString(pns.Items[0].Object, "spec", "defaultInterface"); got != "eno1np0" {
		t.Fatalf("adopted ProviderNetwork spec was mutated: defaultInterface=%q, want eno1np0", got)
	}

	vlans, err := dyn.Resource(vlanGVR).List(context.Background(), listAll())
	if err != nil {
		t.Fatal(err)
	}
	if len(vlans.Items) != 1 {
		var names []string
		for _, i := range vlans.Items {
			names = append(names, i.GetName())
		}
		t.Fatalf("want exactly 1 Vlan (no ext-vlan-702 duplicate), got %d: %v", len(vlans.Items), names)
	}
	if n := vlans.Items[0].GetName(); n != "vlan702" {
		t.Fatalf("Vlan name = %q, want vlan702", n)
	}

	sub, err := dyn.Resource(subnetGVR).Get(context.Background(), "ovn-vpc-external-network", getOpts())
	if err != nil {
		t.Fatalf("external Subnet not created: %v", err)
	}
	if got, _, _ := unstructured.NestedString(sub.Object, "spec", "vlan"); got != "vlan702" {
		t.Fatalf("Subnet.spec.vlan = %q, want the adopted vlan702", got)
	}
}

// TestBootstrap_CreatesWhenNotAdopting: the original behaviour must survive for
// clusters where dc-api owns the SDN.
func TestBootstrap_CreatesWhenNotAdopting(t *testing.T) {
	c, dyn := newFakeClient()
	cfg := lkDevCfg()
	cfg.ProviderNetwork = ""
	cfg.VlanName = ""
	c.WithExternalNetwork(cfg)

	if err := c.EnsureExternalNetworkBootstrap(context.Background()); err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	// bridgeToProviderName truncates at 12 chars: vm-network-br -> vm-network-b
	if _, err := dyn.Resource(providerNetworkGVR).Get(context.Background(), "vm-network-b", getOpts()); err != nil {
		t.Fatalf("want ProviderNetwork vm-network-b created: %v", err)
	}
	if _, err := dyn.Resource(vlanGVR).Get(context.Background(), "ext-vlan-702", getOpts()); err != nil {
		t.Fatalf("want Vlan ext-vlan-702 created: %v", err)
	}
}

// TestBootstrap_AdoptMissingObjectFails: a typo'd adoption name must fail at
// startup, not leave the external network half-wired for the Subnet create to
// trip over with a far less obvious error.
func TestBootstrap_AdoptMissingObjectFails(t *testing.T) {
	for _, tc := range []struct {
		name    string
		objs    []seeded
		wantSub string
	}{
		{"provider network missing", nil, "provider-networks"},
		{"vlan missing", addonObjects()[:1], "vlans"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, _ := newFakeClient(tc.objs...)
			c.WithExternalNetwork(lkDevCfg())
			err := c.EnsureExternalNetworkBootstrap(context.Background())
			if err == nil {
				t.Fatal("want an error when an adopted object is absent")
			}
			if !contains(err.Error(), tc.wantSub) || !contains(err.Error(), "adoption") {
				t.Fatalf("error should name the missing resource and say it must pre-exist, got: %v", err)
			}
		})
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func listAll() metav1.ListOptions { return metav1.ListOptions{} }
func getOpts() metav1.GetOptions  { return metav1.GetOptions{} }

// TestExternalNAD_ClusterNetworkLabel pins how the external NAD's Harvester
// clusternetwork label is chosen. The label must name a real Harvester
// ClusterNetwork; with an adopted provider network the bridge is no longer a
// datapath name, so the explicit setting has to win over the "-br" derivation.
func TestExternalNAD_ClusterNetworkLabel(t *testing.T) {
	const labelKey = "network.harvesterhci.io/clusternetwork"

	cases := []struct {
		name           string
		bridge         string
		clusterNetwork string
		want           string
	}{
		{"explicit wins over derivable bridge", "vm-network-br", "mgmt", "mgmt"},
		{"explicit with real OVS bridge name", "br-ovnpn", "mgmt", "mgmt"},
		{"derived when not set", "vm-network-br", "", "vm-network"},
		{"fallback when bridge has no -br suffix", "br-ovnpn", "", "mgmt"},
		{"fallback for a bare NIC name", "eno1np0", "", "mgmt"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, dyn := newFakeClient(addonObjects()...)
			cfg := lkDevCfg()
			cfg.Bridge = tc.bridge
			cfg.ClusterNetwork = tc.clusterNetwork
			c.WithExternalNetwork(cfg)

			if err := c.EnsureExternalNetworkBootstrap(context.Background()); err != nil {
				t.Fatalf("bootstrap: %v", err)
			}
			nad, err := dyn.Resource(nadGVR).Namespace("kube-system").
				Get(context.Background(), "ovn-vpc-external-network", getOpts())
			if err != nil {
				t.Fatalf("external NAD not created: %v", err)
			}
			got := nad.GetLabels()[labelKey]
			if got != tc.want {
				t.Fatalf("%s = %q, want %q", labelKey, got, tc.want)
			}
		})
	}
}

// TestBootstrap_RefusesSubnetOnWrongVlan covers the migration this adoption
// support exists for: a cluster dc-api already bootstrapped self-managed, now
// pointed at an externally-managed SDN. The external Subnet still carries the
// Vlan dc-api created earlier, so returning early on "it exists" would ignore
// the new configuration, log success, and leave the old ProviderNetwork
// contending for the same physical port.
func TestBootstrap_RefusesSubnetOnWrongVlan(t *testing.T) {
	seed := append(addonObjects(),
		seeded{nadGVR, func() *unstructured.Unstructured {
			u := unstruct("k8s.cni.cncf.io/v1", "NetworkAttachmentDefinition", "ovn-vpc-external-network", nil)
			u.SetNamespace("kube-system")
			return u
		}()},
		// left behind by an earlier self-managed bootstrap
		seeded{subnetGVR, unstruct("kubeovn.io/v1", "Subnet", "ovn-vpc-external-network",
			map[string]interface{}{"vlan": "ext-vlan-702", "cidrBlock": "172.22.101.0/25"})},
	)
	c, _ := newFakeClient(seed...)
	c.WithExternalNetwork(lkDevCfg())

	err := c.EnsureExternalNetworkBootstrap(context.Background())
	if err == nil {
		t.Fatal("want an error when the existing Subnet is on a different vlan")
	}
	for _, want := range []string{"ext-vlan-702", "vlan702", "delete the Subnet"} {
		if !contains(err.Error(), want) {
			t.Fatalf("error should mention %q so an operator knows what to do; got: %v", want, err)
		}
	}
}

// TestBootstrap_RefusesVlanOnWrongProvider: KubeOVN binds a Vlan to the
// ProviderNetwork named in spec.provider, and Subnet validation does not catch
// a mismatch — traffic would ride the wrong uplink silently.
func TestBootstrap_RefusesVlanOnWrongProvider(t *testing.T) {
	c, _ := newFakeClient(
		seeded{providerNetworkGVR, unstruct("kubeovn.io/v1", "ProviderNetwork", "ovnpn",
			map[string]interface{}{"defaultInterface": "eno1np0"})},
		seeded{vlanGVR, unstruct("kubeovn.io/v1", "Vlan", "vlan702",
			map[string]interface{}{"id": int64(702), "provider": "some-other-pn"})},
	)
	c.WithExternalNetwork(lkDevCfg())

	err := c.EnsureExternalNetworkBootstrap(context.Background())
	if err == nil {
		t.Fatal("want an error when the adopted Vlan is on a different provider network")
	}
	if !contains(err.Error(), "some-other-pn") || !contains(err.Error(), "ovnpn") {
		t.Fatalf("error should name both the found and expected provider network; got: %v", err)
	}
}

// TestBootstrap_AdoptsVlanWithDifferentID: with an adopted Vlan, KubeOVN uses
// that Vlan's own id. Requiring it to equal the configured VLANID would reject
// valid setups, so only spec.provider is checked.
func TestBootstrap_AdoptsVlanWithDifferentID(t *testing.T) {
	c, _ := newFakeClient(
		seeded{providerNetworkGVR, unstruct("kubeovn.io/v1", "ProviderNetwork", "ovnpn",
			map[string]interface{}{"defaultInterface": "eno1np0"})},
		seeded{vlanGVR, unstruct("kubeovn.io/v1", "Vlan", "vlan702",
			map[string]interface{}{"id": int64(999), "provider": "ovnpn"})},
	)
	cfg := lkDevCfg()
	cfg.VLANID = 702 // deliberately disagrees with the adopted Vlan's id
	c.WithExternalNetwork(cfg)

	if err := c.EnsureExternalNetworkBootstrap(context.Background()); err != nil {
		t.Fatalf("adopted Vlan id must not be required to match VLANID: %v", err)
	}
}

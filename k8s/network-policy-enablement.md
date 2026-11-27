# Network Policy Enablement for DHDO Kubernetes Stack

## Current State

### Cluster Configuration
- **k3s installed without `--network-policy` flag**
- NetworkPolicy enforcement is **inactive** on the cluster
- No network segmentation between workloads
- All pods can communicate with any other pod in the cluster

### Manifest Status
- NetworkPolicy manifests exist in `k8s/base/networkpolicies/`
- **Not applied** to any environment overlay (dev/tst/acc/prd)
- Current manifests assume **single-namespace** operation
- Stack operates across **4 namespaces**: `irods`, `external`, `public`, `internal`

### Documentation
- `k8s/README.md` (line 598-600) explicitly documents this as current state
- `k8s/base/networkpolicies/deny-and-dns.yaml` contains TODO about multi-namespace support

---

## Why Enable Network Policies?

### Security Benefits
1. **Zero-trust networking**: Default-deny prevents unauthorized pod-to-pod communication
2. **Attack surface reduction**: Limits lateral movement if a pod is compromised
3. **Compliance**: Meets security requirements for workload isolation
4. **iRODS protection**: Specifically secures the 20000-20199 data port range

### Current Risk
Without network policies:
- Any compromised pod can reach any database, service, or internal API
- iRODS data ports (20000-20199) are accessible from any namespace
- No isolation between `public` (customer-facing) and `internal` (admin) workloads

---

## Prerequisites

### 1. k3s Cluster with Network Policy Support

**Required**: k3s must be started with `--network-policy` flag

```bash
# Verify current k3s configuration
systemctl cat k3s.service | grep network-policy

# If not present, k3s needs to be reconfigured
```

### 2. Network Policy Controller

k3s includes **Cilium** as the default network policy provider when `--network-policy` is set. No additional installation required.

---

## Implementation Steps

### Phase 1: Enable k3s Network Policy Support

#### For New Installations
Update the Ansible role to include the flag:

**File**: `/home/rjuhasz/repos/dh-ansible/roles/dh.kubernetes/defaults/main.yml`

```yaml
extra_k3s_args: "--disable=servicelb --network-policy"
```

#### For Existing Cluster
**Warning**: This requires cluster downtime and reconfiguration.

1. Update Ansible role with `--network-policy` flag
2. Re-run Ansible playbook to reconfigure k3s
3. Verify network policy controller is active:

```bash
kubectl get pods -n kube-system | grep cilium
```

### Phase 2: Rework NetworkPolicy Manifests

The current manifests need updates for multi-namespace support.

#### Current Issues
1. **Single-namespace assumption**: Policies reference hardcoded namespaces
2. **Missing cross-namespace rules**: No policies for communication between `irods`, `external`, `public`, `internal`
3. **iRODS port ranges**: Need to allow 20000-20199 from specific namespaces only

#### Required Changes

**File**: `k8s/base/networkpolicies/deny-and-dns.yaml`

Current (simplified):
```yaml
# TODO: Multi-namespace support needed
- name: default-deny
  namespace: ???  # Currently single-namespace
```

Required structure:
```yaml
# Apply to each of the 4 namespaces
namespaces:
  - irods
  - external
  - public
  - internal

# Default deny + DNS allow in each
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: irods  # Repeat for each namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: irods
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

#### Cross-Namespace Communication Rules

**iRODS namespace needs:**
- Allow ingress from `external` namespace on ports 20000-20199 (iRODS data)
- Allow ingress from `external` namespace on port 10000 (iRODS control)
- Allow egress to `external` for database connections
- Allow egress within `irods` namespace for icat<->ires communication

**External namespace needs:**
- Allow ingress from `public` namespace for MDR API calls
- Allow egress to `irods` namespace on iRODS ports

**Public namespace needs:**
- Allow ingress from Traefik (external traffic)
- Allow egress to `external` for MDR API

**Internal namespace needs:**
- Allow ingress from `public` for admin-tools-backend
- Allow egress to `external` for LDAP/Keycloak

### Phase 3: Apply NetworkPolicies

#### Apply to Each Namespace

```bash
# Apply default-deny + DNS to all namespaces
for ns in irods external public internal; do
  kubectl apply -f k8s/base/networkpolicies/deny-and-dns.yaml -n $ns
done

# Apply workload-specific policies
kubectl apply -f k8s/base/networkpolicies/irods-specific.yaml -n irods
kubectl apply -f k8s/base/networkpolicies/external-specific.yaml -n external
kubectl apply -f k8s/base/networkpolicies/public-specific.yaml -n public
kubectl apply -f k8s/base/networkpolicies/internal-specific.yaml -n internal
```

#### Verify Policy Enforcement

```bash
# Check policies are active
kubectl get networkpolicy -A

# Test connectivity (should be blocked without explicit allow)
kubectl -n public run test-pod --rm -it --image=busybox -- sh
# Attempt to reach irods-db: should fail
```

---

## Recommended Timeline

### Immediate (This Sprint)
- [ ] Update Ansible role with `--network-policy` flag
- [ ] Document current state in Confluence (DHDO-2171 worklog)

### Short-Term (2-4 Weeks)
- [ ] Rework `deny-and-dns.yaml` for multi-namespace support
- [ ] Create namespace-specific policy files
- [ ] Test in dev/minikube environment
- [ ] Apply to tst cluster (after k3s reconfiguration)

### Medium-Term (1-2 Months)
- [ ] Validate all workloads with policies enabled
- [ ] Tune policies based on observed traffic patterns
- [ ] Document operational procedures
- [ ] Apply to acc/prd overlays

---

## Testing Checklist

Before applying to production:

- [ ] iCAT can communicate with iRES pods (both namespaces)
- [ ] Garage S3 access works from iRES
- [ ] MDR backend can reach iRODS (external -> irods)
- [ ] Public APIs can reach MDR (public -> external)
- [ ] Admin tools can reach internal services
- [ ] DNS resolution works from all pods
- [ ] No legitimate traffic is blocked
- [ ] Unauthorized traffic is blocked (verified with test pods)

---

## Rollback Plan

If network policies cause issues:

1. **Remove policies** (quick):
   ```bash
   kubectl delete networkpolicy -A
   ```

2. **Disable k3s network policy** (requires restart):
   - Remove `--network-policy` from k3s args
   - Restart k3s service
   - Note: This is a cluster-wide change

---

## Related Files

- `/home/rjuhasz/repos/dh-env/docker-dev/k8s/base/networkpolicies/` - Current manifests
- `/home/rjuhasz/repos/dh-ansible/roles/dh.kubernetes/defaults/main.yml` - k3s args
- `/home/rjuhasz/repos/dh-env/docker-dev/k8s/README.md` - Documentation (line 598-600)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking legitimate traffic | Medium | High | Test in dev first; gradual rollout |
| k3s reconfiguration downtime | Low | Medium | Schedule maintenance window |
| Policy complexity errors | Medium | Medium | Use kubectl dry-run; peer review |
| Performance overhead | Low | Low | Cilium is efficient; monitor |

---

## Success Criteria

Network policies are considered successfully enabled when:

1. k3s running with `--network-policy` flag (verified)
2. Default-deny policies active in all 4 namespaces
3. All workloads communicating correctly with policies enabled
4. Unauthorized traffic blocked (verified with test cases)
5. Documentation updated with operational procedures
6. Team trained on policy modification process

---

## Contact

For questions or issues:
- Review findings: DHDO-2171 Code Review Worklog
- Technical details: `k8s/base/networkpolicies/` manifests
- Cluster config: Ansible role `dh.kubernetes`

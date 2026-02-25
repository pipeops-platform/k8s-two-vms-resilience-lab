# Technical Assessment – Question 2
## Kubernetes Cluster on Two VMs (Practical Development)

## 1. Objective

Build a small, reproducible Kubernetes environment on two VMs using **Ansible** (mandatory), deploy a workload that is spread across both nodes, and demonstrate that traffic is still served during specific disruptions.

### Requested topology
- **VM1**: Control-plane (also schedulable as worker)
- **VM2**: Worker

### Key requirement
- Workload must run across both nodes and continue serving traffic when one node/workload instance is disrupted.

---

## 2. Design Choices and Rationale

### Why `kubeadm` (preferred)
- Matches the requirement directly.
- Demonstrates understanding of core Kubernetes bootstrap steps (PKI, init, join, control-plane setup).
- Better signal for production-like operations knowledge than hiding details behind higher-level wrappers.

### Why Ansible-only for provisioning/configuration
- Enforces repeatability and idempotency.
- Keeps setup auditable and easy to re-run.
- Directly satisfies the “Ansible required” constraint.

### Why not Terraform for this delivery
- Terraform is optional and adds scope overhead for this take-home.
- VM creation can be assumed pre-existing; the assessment value is in cluster automation and resilience behavior.

---

## 3. Proposed Repository Structure

```text
assessment-k8s-2vms/
  README.md
  ansible/
    ansible.cfg
    inventory.ini
    group_vars/
      all.yml
    playbooks/
      00-prereqs.yml
      01-container-runtime.yml
      02-kubernetes-packages.yml
      03-kubeadm-init.yml
      04-join-worker.yml
      05-cni-calico.yml
      06-labels-taints.yml
      07-verify.yml
  k8s/
    namespace.yml
    deployment.yml
    service-nodeport.yml
    pdb.yml
    hpa.yml (optional)
  scripts/
    smoke_test.sh
    disruption_worker_down.sh
    disruption_drain_controlplane.sh
  .github/
    workflows/
      ci.yml
```

---

## 4. Environment Assumptions

- Ubuntu 22.04 LTS on both VMs
- Private network between VMs (example: `10.0.0.0/24`)
- SSH access from Ansible control host
- Sudo privileges
- Outbound internet allowed for package installation
- Static hostnames:
  - `vm1-control`
  - `vm2-worker`

Example IPs:
- VM1: `10.0.0.11`
- VM2: `10.0.0.12`

---

## 5. Practical Implementation Steps

## Step 1 — Base OS prerequisites (Ansible)

Playbook `00-prereqs.yml`:
- Disable swap permanently (`swapoff -a` and `/etc/fstab` update)
- Enable required kernel modules (`overlay`, `br_netfilter`)
- Set sysctls:
  - `net.bridge.bridge-nf-call-iptables=1`
  - `net.ipv4.ip_forward=1`
  - `net.bridge.bridge-nf-call-ip6tables=1`
- Install baseline tools (`curl`, `apt-transport-https`, `ca-certificates`, `jq`)

Validation:
- `swapon --show` returns empty.
- `sysctl net.ipv4.ip_forward` returns `1`.

## Step 2 — Container runtime setup

Playbook `01-container-runtime.yml`:
- Install `containerd`.
- Generate default `/etc/containerd/config.toml`.
- Set `SystemdCgroup = true`.
- Enable and start `containerd`.

Validation:
- `systemctl is-active containerd` = `active`.

## Step 3 — Kubernetes packages installation

Playbook `02-kubernetes-packages.yml`:
- Add official Kubernetes apt repository.
- Install `kubelet`, `kubeadm`, `kubectl` (pinned version, e.g. `1.30.x`).
- Hold package versions to avoid accidental upgrades.

Validation:
- `kubeadm version`
- `kubelet --version`

## Step 4 — Initialize control-plane

Playbook `03-kubeadm-init.yml` (runs on VM1):
- Run `kubeadm init` with explicit pod CIDR (example `192.168.0.0/16` for Calico).
- Configure admin kubeconfig (`/root/.kube/config` and optionally copied to non-root user).
- Extract and store join command securely for worker playbook.

Important decision:
- Remove control-plane taint to allow scheduling on VM1 (as requested practical topology):
  - `kubectl taint nodes vm1-control node-role.kubernetes.io/control-plane-`

Validation:
- `kubectl get nodes` shows VM1 `Ready`.

## Step 5 — Join worker node

Playbook `04-join-worker.yml` (runs on VM2):
- Execute join command generated from control-plane.
- Ensure kubelet healthy after join.

Validation:
- `kubectl get nodes -o wide` shows VM2 `Ready`.

## Step 6 — Install CNI (Calico)

Playbook `05-cni-calico.yml`:
- Apply Calico manifests.
- Wait for `calico-node` DaemonSet rollout.

Validation:
- `kubectl -n kube-system get pods` shows networking components healthy.

## Step 7 — Labels, taints, and scheduling policy

Playbook `06-labels-taints.yml`:
- Add explicit labels for clarity:
  - `topology.kubernetes.io/zone=vm1` / `vm2` (or custom labels)
  - role labels if needed for affinity rules.

Validation:
- `kubectl get nodes --show-labels`.

## Step 8 — Deploy resilient workload

Resources:
1. `namespace.yml`
2. `deployment.yml`
3. `service-nodeport.yml`
4. `pdb.yml`

### Deployment requirements
- `replicas: 2`
- Pod anti-affinity required by hostname to force one pod per node:
  - `requiredDuringSchedulingIgnoredDuringExecution` on `kubernetes.io/hostname`
- Resource requests/limits defined
- Readiness and liveness probes enabled
- `terminationGracePeriodSeconds` set reasonably

### Service exposure
- Use `NodePort` for simple two-VM demonstration.
- Validate access through either VM IP + NodePort.

### PDB
- `minAvailable: 1` to keep at least one pod serving during voluntary disruptions (e.g., drain).

Validation:
- `kubectl get pods -o wide -n demo` should show pods on both nodes.
- Repeated curl to NodePort returns successful responses.

---

## 6. Disruption Scenarios and Proof of Resilience

## Scenario A — Worker node failure (VM2 down)

Test procedure:
1. Start continuous traffic from a client machine:
   - `while true; do curl -sS http://10.0.0.11:<nodePort>/health; sleep 1; done`
2. Stop VM2 (or block network).
3. Observe pod/node events and service availability.

Expected result:
- One replica becomes unavailable.
- Remaining replica on VM1 keeps serving traffic.
- Some transient failures may occur during endpoint updates, but service should recover quickly.

Evidence to capture:
- `kubectl get nodes`
- `kubectl get pods -o wide -n demo`
- Curl output with timestamps.

## Scenario B — Voluntary disruption via drain on VM1

Test procedure:
1. `kubectl drain vm1-control --ignore-daemonsets --delete-emptydir-data`
2. Observe rescheduling behavior.
3. Continue curl traffic checks.
4. `kubectl uncordon vm1-control` after validation.

Expected result:
- With PDB and anti-affinity, workload keeps one healthy serving replica.
- Service remains reachable through worker NodePort path.

Evidence to capture:
- Drain command output.
- Pod movement timeline.
- Zero/low impact traffic log.

---

## 7. What “Continue Serving Traffic” Means Here

In a 2-node non-HA control-plane topology, realistic interpretation is:
- The workload endpoint remains available to clients during node/pod disruptions, assuming at least one worker pod remains healthy.
- Kubernetes API/control-plane management may be partially impacted if VM1 is down, but existing data-plane traffic can still be served by remaining node endpoints.

This distinction should be explicitly documented to show operational realism.

---

## 8. CI/CD Quality Gate (GitHub Actions)

Recommended lightweight CI (`.github/workflows/ci.yml`):
- `ansible-lint` for Ansible content
- `yamllint` for YAML
- `kubeconform` for Kubernetes manifests
- `shellcheck` for shell scripts
- Optional `markdownlint` for docs

Why this is valuable:
- Demonstrates engineering quality and reproducibility.
- Avoids fragile “spin up VMs in CI” complexity.

---

## 9. Example Commands (Execution Order)

```bash
# 1) Run cluster bootstrap
ansible-playbook -i ansible/inventory.ini ansible/playbooks/00-prereqs.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/01-container-runtime.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/02-kubernetes-packages.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/03-kubeadm-init.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/04-join-worker.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/05-cni-calico.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/06-labels-taints.yml

# 2) Deploy workload
kubectl apply -f k8s/namespace.yml
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service-nodeport.yml
kubectl apply -f k8s/pdb.yml

# 3) Validate placement and health
kubectl get nodes -o wide
kubectl get pods -n demo -o wide
kubectl get svc -n demo
```

---

## 10. Risks and Mitigations

1. **Single control-plane is a SPOF for management plane**
   - Mitigation: clearly state limitation; focus resilience test on data plane continuity.
2. **NodePort exposure is basic**
   - Mitigation: acceptable for assessment simplicity; mention LoadBalancer/Ingress as production evolution.
3. **Version drift in packages/manifests**
   - Mitigation: pin versions in Ansible vars and document tested versions.
4. **Scheduling not truly spread if anti-affinity misconfigured**
   - Mitigation: enforce required anti-affinity and verify with pod placement checks.

---

## 11. Deliverables Checklist

- [ ] Ansible inventory and playbooks for full cluster bring-up
- [ ] Kubernetes manifests for resilient workload
- [ ] PDB and anti-affinity policy demonstrated
- [ ] Disruption test scripts and captured outputs
- [ ] README with run instructions and known limitations
- [ ] CI workflow for lint/validation

---

## 12. Suggested README Evidence Section

Include in final repository:
- Environment details (OS, Kubernetes version, VM specs)
- Command log excerpts
- `kubectl get nodes/pods/services` outputs
- Disruption test timeline
- Availability observations and recovery timing
- Known constraints and next improvements

---

## 13. Conclusion

This implementation demonstrates practical Kubernetes operations on a constrained two-VM topology with automation-first delivery through Ansible. It proves workload distribution across nodes, validates continuity of traffic under realistic disruptions, and documents limitations transparently. The approach is intentionally pragmatic for a take-home setting while still reflecting production-minded engineering practices.

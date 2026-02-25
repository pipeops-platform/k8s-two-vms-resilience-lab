# Kubernetes Two VMs Resilience Lab

Practical delivery for Technical Assessment – Question 2.

## Goal

Build a small Kubernetes cluster on two VMs and demonstrate workload availability under disruption scenarios.

Topology:

- VM1: control-plane (schedulable)
- VM2: worker

Tooling:

- Ansible required
- kubeadm preferred

## Repository Contents

- Main technical document: `TECHNICAL_ASSESSMENT_Q2_K8S_TWO_VMS_PRACTICAL_DEVELOPMENT.md`
- Ansible automation skeleton in `ansible/`
- Kubernetes manifests in `k8s/`
- Disruption and smoke scripts in `scripts/`

## Repository Structure

```text
.
├── README.md
├── TECHNICAL_ASSESSMENT_Q2_K8S_TWO_VMS_PRACTICAL_DEVELOPMENT.md
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini.example
│   ├── group_vars/all.yml
│   └── playbooks/
│       ├── 00-prereqs.yml
│       ├── 01-container-runtime.yml
│       ├── 02-kubernetes-packages.yml
│       ├── 03-kubeadm-init.yml
│       ├── 04-join-worker.yml
│       ├── 05-cni-calico.yml
│       ├── 06-labels-taints.yml
│       └── 07-verify.yml
├── k8s/
│   ├── namespace.yml
│   ├── deployment.yml
│   ├── service-nodeport.yml
│   └── pdb.yml
└── scripts/
	├── smoke_test.sh
	├── disruption_worker_down.sh
	└── disruption_drain_controlplane.sh
```

## What this submission demonstrates

- Reproducible cluster setup strategy with Ansible
- Workload spread across both nodes (anti-affinity)
- Traffic continuity under node/workload disruption
- Clear operational limitations and realistic expectations for 2-node topology

## Execution Model (summary)

1. Provision prerequisites on both VMs
2. Install container runtime and Kubernetes packages
3. Initialize control-plane on VM1 with kubeadm
4. Join VM2 as worker
5. Install CNI (Calico)
6. Deploy resilient sample workload (2 replicas + anti-affinity + probes + PDB)
7. Validate service continuity with continuous traffic while introducing disruptions

## Disruption tests

Required scenarios:

- Worker node down (VM2 failure)
- Voluntary disruption (drain VM1)

Expected behavior:

- At least one pod remains available
- Service remains reachable after short convergence window

## Evidence to capture

During execution, capture and include:

- `kubectl get nodes -o wide`
- `kubectl get pods -n demo -o wide`
- `kubectl get svc -n demo`
- Continuous curl output with timestamps
- Drain/failure event timeline and recovery observations

## Limitations (explicit)

- Single control-plane is a management-plane SPOF
- This lab validates data-plane continuity, not full HA control-plane behavior

## How to use this repo

- Read the complete implementation and rationale in:
	- `TECHNICAL_ASSESSMENT_Q2_K8S_TWO_VMS_PRACTICAL_DEVELOPMENT.md`
- Execute using the sequence and validation checkpoints documented there

## Quick Run (commands)

1) Prepare inventory:

- Copy `ansible/inventory.ini.example` to `ansible/inventory.ini`
- Update IPs/users for your VMs

2) Bootstrap cluster:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/00-prereqs.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/01-container-runtime.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/02-kubernetes-packages.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/03-kubeadm-init.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/04-join-worker.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/05-cni-calico.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/06-labels-taints.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/07-verify.yml
```

3) Deploy workload:

```bash
kubectl apply -f k8s/namespace.yml
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service-nodeport.yml
kubectl apply -f k8s/pdb.yml
```

4) Run validations:

```bash
bash scripts/smoke_test.sh http://10.0.0.11:30080
bash scripts/disruption_worker_down.sh http://10.0.0.11:30080
bash scripts/disruption_drain_controlplane.sh vm1-control http://10.0.0.12:30080
```

## Submission checklist

- [x] Architecture and approach documented
- [x] kubeadm + Ansible strategy defined
- [x] Resilience scenarios specified
- [x] Validation commands and expected outcomes included
- [ ] Runtime evidence attached (logs/output/screenshots)
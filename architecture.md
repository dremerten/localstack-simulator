# Architecture Overview

## Goal
Provide a hostile-by-default, browser-based terminal for practicing AWS workflows against LocalStack. The design assumes untrusted users and minimizes privileges, persistence, and network access.

## Components
- **Gateway**: lightweight TCP proxy that exposes port 5446 on the host and forwards to the sandbox terminal.
- **Sandbox**: non-root container running ttyd, AWS CLI, Terraform, Pulumi (Python), Ansible, and helper tools. Read-only root FS with a seeded `/workspace`.
- **LocalStack**: AWS API emulator for S3, IAM, STS, Lambda, EC2, ELB/ALB, Auto Scaling, RDS, and Route 53.

## Trust Boundaries
- **Untrusted user** sits inside the sandbox shell.
- **Sandbox container** has no Docker socket, no capabilities, and read-only root.
- **LocalStack** isolated on internal network.
- **Host** only sees a single exposed port from the gateway.

## Data Flow
1) User hits host port 5446.
2) Gateway forwards traffic to sandbox ttyd.
3) Sandbox tools call LocalStack via internal network.

## Workloads
- **Terraform HA stack**: two-region VPCs with public/private subnets, IGWs, NAT gateways, ALB + Auto Scaling, RDS (multi-AZ), Route 53 private DNS, and S3 security guardrails.
- **Pulumi HA stack**: Python implementation with a simulated mode for LocalStack Community and a full mode for LocalStack Pro.

## Security Principles
- Least privilege (non-root, drop all caps, no-new-privileges).
- No host mounts other than a dedicated workspace volume.
- Read-only root filesystem with tmpfs for runtime paths.
- Internal network to prevent egress except LocalStack.

## Diagram
See `docs/diagram.mmd`.

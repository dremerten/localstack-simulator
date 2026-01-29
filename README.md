# Local Cloud Sandbox

Project Created By Andre Merten, 2026

This environment is a safe, isolated practice lab for cloud and infrastructure workflows. It also demonstrates my knowledge of Infrastructure as Code, security best practices in cloud and system design, and high availability. It gives you a real Linux terminal in the browser and a LocalStack-backed AWS API so you can experiment without touching real AWS or exposing the host.

What this sandbox is for
- Practice Infrastructure as Code and configuration management using Terraform, Pulumi (Python), and Ansible.
- Learn how a highly available AWS-style architecture is composed (multi-region networking, compute, load balancing, storage, and databases).
- Explore security best practices such as private subnets, encryption, and least-privilege IAM.

How it works (high level)
- The sandbox is ephemeral. All work is confined to `/workspace` and resets on each new session.
- LocalStack provides the AWS-compatible endpoints; nothing leaves the sandbox.
- Reference code and examples live under `/workspace/terraform`, `/workspace/ansible`, and `/workspace/pulumi/python`.

To see all available commands, run:
```
make help
```
- Workspace code resets to defaults on each new login (including page refresh).
- `cd` is restricted to `/workspace` (and `/home/sandbox`) only.

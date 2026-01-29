import inspect
import os

import pulumi
import pulumi_aws as aws

config = pulumi.Config()
simulate = config.get_bool("simulateUnsupported")
if simulate is None:
    simulate = True

alb_count = config.get_int("albCount") or 3
az_count = config.get_int("azCount") or 3
asg_min_size = config.get_int("asgMinSize") or 3
asg_max_size = config.get_int("asgMaxSize") or 6
asg_desired_capacity = config.get_int("asgDesiredCapacity") or 3

def is_localstack_pro() -> bool:
    if (os.getenv("LOCALSTACK_PRO", "") or "").lower() in ("1", "true", "yes"):
        return True
    if os.getenv("LOCALSTACK_AUTH_TOKEN") or os.getenv("LOCALSTACK_API_KEY"):
        return True
    return (os.getenv("LOCALSTACK_TIER", "") or "").lower() == "pro"

if simulate is False and not is_localstack_pro():
    pulumi.log.warn("LocalStack Pro not detected; using simulated resources.")
    simulate = True

primary_region = config.get("primaryRegion") or "us-east-1"
secondary_region = config.get("secondaryRegion") or "us-west-2"

localstack_endpoint = os.getenv("LOCALSTACK_ENDPOINT", "http://localstack:4566")

def provider_for(region: str):
    endpoint_keys = set(inspect.signature(aws.ProviderEndpointArgs.__init__).parameters.keys())
    endpoint_keys.discard("self")

    endpoint_map = {
        "s3": ["s3"],
        "iam": ["iam"],
        "sts": ["sts"],
        "ec2": ["ec2"],
        "autoscaling": ["autoscaling"],
        "elb": ["elb"],
        "elbv2": ["elbv2"],
        "acm": ["acm"],
        "rds": ["rds"],
        "route53": ["route53"],
    }

    endpoint_kwargs = {}
    supported = {}
    for name, candidates in endpoint_map.items():
        for key in candidates:
            if key in endpoint_keys:
                endpoint_kwargs[key] = localstack_endpoint
                supported[name] = True
                break
        else:
            supported[name] = False

    endpoints = None
    if endpoint_kwargs:
        endpoints = [aws.ProviderEndpointArgs(**endpoint_kwargs)]

    access_key = os.getenv("AWS_ACCESS_KEY_ID", "test")
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY", "test")

    provider = aws.Provider(
        f"localstack-{region}",
        region=region,
        access_key=access_key,
        secret_key=secret_key,
        skip_credentials_validation=True,
        skip_metadata_api_check=True,
        skip_requesting_account_id=True,
        s3_use_path_style=True,
        endpoints=endpoints,
        default_tags=aws.ProviderDefaultTagsArgs(
            tags={
                "project": "sandbox",
                "env": "dev",
                "region": region,
            }
        ),
    )

    return provider, supported


class SimulatedResource(pulumi.ComponentResource):
    def __init__(self, name: str, outputs: dict, opts: pulumi.ResourceOptions | None = None):
        super().__init__("sandbox:simulated:Resource", name, {}, opts)
        self.register_outputs(outputs)


def build_region(prefix: str, region: str, cidr: str):
    provider, supported = provider_for(region)
    opts = pulumi.ResourceOptions(provider=provider)

    tags = {
        "project": "sandbox",
        "env": "dev",
        "region": region,
        "component": prefix,
    }

    vpc = aws.ec2.Vpc(
        f"{prefix}-vpc",
        cidr_block=cidr,
        enable_dns_support=True,
        enable_dns_hostnames=True,
        tags=tags,
        opts=opts,
    )

    igw = aws.ec2.InternetGateway(
        f"{prefix}-igw",
        vpc_id=vpc.id,
        tags=tags,
        opts=opts,
    )

    octets = cidr.split(".")
    base = f"{octets[0]}.{octets[1]}"
    az_letters = ["a", "b", "c", "d", "e", "f"]
    azs = [f"{region}{az_letters[i]}" for i in range(az_count)]
    public_cidrs = [f"{base}.{i}.0/24" for i in range(az_count)]
    private_cidrs = [f"{base}.{10 + i}.0/24" for i in range(az_count)]

    public_subnets = []
    private_subnets = []
    for i in range(az_count):
        public_subnets.append(
            aws.ec2.Subnet(
                f"{prefix}-public-{i+1}",
                vpc_id=vpc.id,
                cidr_block=public_cidrs[i],
                availability_zone=azs[i],
                map_public_ip_on_launch=True,
                tags={**tags, "tier": "public"},
                opts=opts,
            )
        )
        private_subnets.append(
            aws.ec2.Subnet(
                f"{prefix}-private-{i+1}",
                vpc_id=vpc.id,
                cidr_block=private_cidrs[i],
                availability_zone=azs[i],
                map_public_ip_on_launch=False,
                tags={**tags, "tier": "private"},
                opts=opts,
            )
        )

    public_rt = aws.ec2.RouteTable(
        f"{prefix}-public-rt",
        vpc_id=vpc.id,
        tags={**tags, "tier": "public"},
        opts=opts,
    )
    aws.ec2.Route(
        f"{prefix}-public-igw",
        route_table_id=public_rt.id,
        destination_cidr_block="0.0.0.0/0",
        gateway_id=igw.id,
        opts=opts,
    )
    for idx, subnet in enumerate(public_subnets, start=1):
        aws.ec2.RouteTableAssociation(
            f"{prefix}-public-assoc-{idx}",
            subnet_id=subnet.id,
            route_table_id=public_rt.id,
            opts=opts,
        )

    nat_gateways = []
    if not simulate:
        for idx, subnet in enumerate(public_subnets, start=1):
            eip = aws.ec2.Eip(
                f"{prefix}-nat-eip-{idx}",
                domain="vpc",
                tags=tags,
                opts=opts,
            )
            nat_gateways.append(
                aws.ec2.NatGateway(
                    f"{prefix}-nat-{idx}",
                    allocation_id=eip.id,
                    subnet_id=subnet.id,
                    tags=tags,
                    opts=opts,
                )
            )

    for idx, subnet in enumerate(private_subnets, start=1):
        private_rt = aws.ec2.RouteTable(
            f"{prefix}-private-rt-{idx}",
            vpc_id=vpc.id,
            tags={**tags, "tier": "private"},
            opts=opts,
        )
        if not simulate:
            aws.ec2.Route(
                f"{prefix}-private-nat-{idx}",
                route_table_id=private_rt.id,
                destination_cidr_block="0.0.0.0/0",
                nat_gateway_id=nat_gateways[idx - 1].id,
                opts=opts,
            )
        aws.ec2.RouteTableAssociation(
            f"{prefix}-private-assoc-{idx}",
            subnet_id=subnet.id,
            route_table_id=private_rt.id,
            opts=opts,
        )

    bucket = aws.s3.Bucket(
        f"{prefix}-app-bucket",
        force_destroy=True,
        tags=tags,
        opts=opts,
    )
    aws.s3.BucketVersioning(
        f"{prefix}-bucket-versioning",
        bucket=bucket.id,
        versioning_configuration=aws.s3.BucketVersioningVersioningConfigurationArgs(
            status="Enabled"
        ),
        opts=opts,
    )
    aws.s3.BucketPublicAccessBlock(
        f"{prefix}-bucket-block",
        bucket=bucket.id,
        block_public_acls=True,
        block_public_policy=True,
        ignore_public_acls=True,
        restrict_public_buckets=True,
        opts=opts,
    )
    aws.s3.BucketServerSideEncryptionConfiguration(
        f"{prefix}-bucket-sse",
        bucket=bucket.id,
        rules=[
            aws.s3.BucketServerSideEncryptionConfigurationRuleArgs(
                apply_server_side_encryption_by_default=aws.s3.BucketServerSideEncryptionConfigurationRuleApplyServerSideEncryptionByDefaultArgs(
                    sse_algorithm="AES256"
                )
            )
        ],
        opts=opts,
    )
    aws.s3.BucketOwnershipControls(
        f"{prefix}-bucket-ownership",
        bucket=bucket.id,
        rule=aws.s3.BucketOwnershipControlsRuleArgs(
            object_ownership="BucketOwnerEnforced"
        ),
        opts=opts,
    )

    assume_role_policy = aws.iam.get_policy_document(
        statements=[
            aws.iam.GetPolicyDocumentStatementArgs(
                actions=["sts:AssumeRole"],
                principals=[
                    aws.iam.GetPolicyDocumentStatementPrincipalArgs(
                        type="Service",
                        identifiers=["ec2.amazonaws.com"],
                    )
                ],
            )
        ],
        opts=pulumi.InvokeOptions(provider=provider),
    )

    role = aws.iam.Role(
        f"{prefix}-app-role",
        assume_role_policy=assume_role_policy.json,
        tags=tags,
        opts=opts,
    )

    aws.iam.RolePolicy(
        f"{prefix}-app-policy",
        role=role.id,
        policy=bucket.arn.apply(
            lambda arn: aws.iam.get_policy_document(
                statements=[
                    aws.iam.GetPolicyDocumentStatementArgs(
                        actions=["s3:ListBucket"],
                        resources=[arn],
                    ),
                    aws.iam.GetPolicyDocumentStatementArgs(
                        actions=["s3:GetObject"],
                        resources=[f"{arn}/*"],
                    ),
                ],
                opts=pulumi.InvokeOptions(provider=provider),
            ).json
        ),
        opts=opts,
    )

    instance_profile = aws.iam.InstanceProfile(
        f"{prefix}-instance-profile",
        role=role.name,
        opts=opts,
    )

    alb_sg = aws.ec2.SecurityGroup(
        f"{prefix}-alb-sg",
        vpc_id=vpc.id,
        description="Allow HTTP/HTTPS to ALB",
        ingress=[
            aws.ec2.SecurityGroupIngressArgs(
                protocol="tcp",
                from_port=80,
                to_port=80,
                cidr_blocks=["0.0.0.0/0"],
            ),
            aws.ec2.SecurityGroupIngressArgs(
                protocol="tcp",
                from_port=443,
                to_port=443,
                cidr_blocks=["0.0.0.0/0"],
            ),
        ],
        egress=[
            aws.ec2.SecurityGroupEgressArgs(
                protocol="-1",
                from_port=0,
                to_port=0,
                cidr_blocks=["0.0.0.0/0"],
            )
        ],
        tags=tags,
        opts=opts,
    )

    app_sg = aws.ec2.SecurityGroup(
        f"{prefix}-app-sg",
        vpc_id=vpc.id,
        description="Allow HTTP from ALB",
        ingress=[
            aws.ec2.SecurityGroupIngressArgs(
                protocol="tcp",
                from_port=80,
                to_port=80,
                security_groups=[alb_sg.id],
            )
        ],
        egress=[
            aws.ec2.SecurityGroupEgressArgs(
                protocol="-1",
                from_port=0,
                to_port=0,
                cidr_blocks=["0.0.0.0/0"],
            )
        ],
        tags=tags,
        opts=opts,
    )

    db_sg = aws.ec2.SecurityGroup(
        f"{prefix}-db-sg",
        vpc_id=vpc.id,
        description="Allow MySQL from app",
        ingress=[
            aws.ec2.SecurityGroupIngressArgs(
                protocol="tcp",
                from_port=3306,
                to_port=3306,
                security_groups=[app_sg.id],
            )
        ],
        egress=[
            aws.ec2.SecurityGroupEgressArgs(
                protocol="-1",
                from_port=0,
                to_port=0,
                cidr_blocks=["0.0.0.0/0"],
            )
        ],
        tags=tags,
        opts=opts,
    )

    can_elb = supported.get("elbv2", False) or supported.get("elb", False)
    can_asg = supported.get("autoscaling", False)
    can_rds = supported.get("rds", False)
    can_route53 = supported.get("route53", False)

    alb_dns = []
    albs = []
    tgs = []
    if not simulate and can_elb and can_asg:
        cert = aws.acm.Certificate(
            f"{prefix}-alb-cert",
            domain_name=f"app.{prefix}.local",
            validation_method="DNS",
            tags=tags,
            opts=opts,
        )

        for idx in range(alb_count):
            alb = aws.lb.LoadBalancer(
                f"{prefix}-alb-{idx + 1}",
                load_balancer_type="application",
                internal=False,
                security_groups=[alb_sg.id],
                subnets=[s.id for s in public_subnets],
                tags=tags,
                opts=opts,
            )

            tg = aws.lb.TargetGroup(
                f"{prefix}-tg-{idx + 1}",
                port=80,
                protocol="HTTP",
                target_type="instance",
                vpc_id=vpc.id,
                health_check=aws.lb.TargetGroupHealthCheckArgs(
                    path="/",
                    protocol="HTTP",
                ),
                tags=tags,
                opts=opts,
            )

            aws.lb.Listener(
                f"{prefix}-listener-{idx + 1}",
                load_balancer_arn=alb.arn,
                port=80,
                protocol="HTTP",
                default_actions=[
                    aws.lb.ListenerDefaultActionArgs(
                        type="forward",
                        target_group_arn=tg.arn,
                    )
                ],
                opts=opts,
            )

            aws.lb.Listener(
                f"{prefix}-listener-https-{idx + 1}",
                load_balancer_arn=alb.arn,
                port=443,
                protocol="HTTPS",
                ssl_policy="ELBSecurityPolicy-2016-08",
                certificate_arn=cert.arn,
                default_actions=[
                    aws.lb.ListenerDefaultActionArgs(
                        type="forward",
                        target_group_arn=tg.arn,
                    )
                ],
                opts=opts,
            )

            albs.append(alb)
            tgs.append(tg)

        user_data = """#!/bin/bash
echo 'Hello from LocalStack' > /var/www/html/index.html
"""

        lt = aws.ec2.LaunchTemplate(
            f"{prefix}-lt",
            image_id="ami-12345678",
            instance_type="t3.micro",
            user_data=user_data,
            iam_instance_profile=aws.ec2.LaunchTemplateIamInstanceProfileArgs(
                name=instance_profile.name
            ),
            vpc_security_group_ids=[app_sg.id],
            metadata_options=aws.ec2.LaunchTemplateMetadataOptionsArgs(
                http_tokens="required"
            ),
            tags=tags,
            opts=opts,
        )

        aws.autoscaling.Group(
            f"{prefix}-asg",
            desired_capacity=asg_desired_capacity,
            max_size=asg_max_size,
            min_size=asg_min_size,
            vpc_zone_identifiers=[s.id for s in private_subnets],
            launch_template=aws.autoscaling.GroupLaunchTemplateArgs(
                id=lt.id,
                version="$Latest",
            ),
            target_group_arns=[tg.arn for tg in tgs],
            health_check_type="EC2",
            tags=[
                aws.autoscaling.GroupTagArgs(
                    key="Name",
                    value=f"{prefix}-app",
                    propagate_at_launch=True,
                )
            ],
            opts=opts,
        )

        alb_dns = [alb.dns_name for alb in albs]
    else:
        for idx in range(alb_count):
            sim_dns = pulumi.Output.from_input(f"simulated-alb-{idx + 1}")
            SimulatedResource(
                f"{prefix}-alb-{idx + 1}",
                {"dnsName": sim_dns},
                opts=opts,
            )
            alb_dns.append(sim_dns)

    rds_endpoint = pulumi.Output.from_input("simulated-rds")
    if not simulate and can_rds:
        db_username = config.get("dbUsername") or os.getenv("DB_USERNAME") or "appuser"
        db_password = config.get_secret("dbPassword")
        if db_password is None:
            env_password = os.getenv("DB_PASSWORD")
            if env_password:
                db_password = pulumi.Output.secret(env_password)
            else:
                db_password = pulumi.Output.secret("localstack123")

        subnet_group = aws.rds.SubnetGroup(
            f"{prefix}-db-subnets",
            subnet_ids=[s.id for s in private_subnets],
            tags=tags,
            opts=opts,
        )

        db = aws.rds.Instance(
            f"{prefix}-db",
            allocated_storage=20,
            engine="mysql",
            engine_version="8.4.0",
            instance_class="db.t3.micro",
            db_subnet_group_name=subnet_group.name,
            vpc_security_group_ids=[db_sg.id],
            username=db_username,
            password=db_password,
            multi_az=True,
            storage_encrypted=True,
            backup_retention_period=7,
            skip_final_snapshot=True,
            publicly_accessible=False,
            tags=tags,
            opts=opts,
        )

        rds_endpoint = db.endpoint
    else:
        SimulatedResource(
            f"{prefix}-rds",
            {"endpoint": rds_endpoint},
            opts=opts,
        )

    if not simulate and can_route53:
        zone = aws.route53.Zone(
            f"{prefix}-zone",
            name=f"{prefix}.local",
            tags=tags,
            opts=opts,
        )
        for idx, alb in enumerate(albs, start=1):
            aws.route53.Record(
                f"{prefix}-app-dns-{idx}",
                zone_id=zone.id,
                name=f"app.{prefix}.local",
                type="CNAME",
                ttl=60,
                records=[alb.dns_name],
                set_identifier=f"alb-{idx}",
                weighted_routing_policy=aws.route53.RecordWeightedRoutingPolicyArgs(
                    weight=1
                ),
                opts=opts,
            )
    else:
        SimulatedResource(
            f"{prefix}-dns",
            {"hostname": pulumi.Output.from_input(f"app.{prefix}.local")},
            opts=opts,
        )

    return {
        "vpc_id": vpc.id,
        "public_subnet_ids": [s.id for s in public_subnets],
        "private_subnet_ids": [s.id for s in private_subnets],
        "bucket_name": bucket.id,
        "alb_dns": alb_dns,
        "rds_endpoint": rds_endpoint,
    }


primary = build_region("primary", primary_region, "10.0.0.0/16")
secondary = build_region("secondary", secondary_region, "10.1.0.0/16")

pulumi.export("primary_vpc_id", primary["vpc_id"])
pulumi.export("secondary_vpc_id", secondary["vpc_id"])
pulumi.export("primary_alb_dns", primary["alb_dns"])
pulumi.export("secondary_alb_dns", secondary["alb_dns"])
pulumi.export("primary_bucket", primary["bucket_name"])
pulumi.export("secondary_bucket", secondary["bucket_name"])
pulumi.export("primary_rds_endpoint", primary["rds_endpoint"])
pulumi.export("secondary_rds_endpoint", secondary["rds_endpoint"])

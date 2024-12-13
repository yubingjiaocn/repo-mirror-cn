#!/usr/bin/env python3
import ipaddress
from typing import List
import requests

def fetch_aws_ip_ranges(region: str = "cn-north-1") -> List[str]:
    """Fetch IP ranges for specified AWS region."""
    url = "https://ip-ranges.amazonaws.com/ip-ranges.json"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        # Extract and deduplicate IP prefixes for the specified region
        ip_prefixes = list(set(prefix["ip_prefix"] for prefix in data["prefixes"]
                             if prefix["region"] == region))
        # Sort by IP and prefix length using ipaddress module for correct IP sorting
        return sorted(ip_prefixes,
                     key=lambda x: (ipaddress.IPv4Network(x).network_address,
                                  ipaddress.IPv4Network(x).prefixlen))
    except requests.RequestException as e:
        print(f"Error fetching AWS IP ranges: {e}")
        return []

def parse_cidrs(cidrs: List[str]) -> List[ipaddress.IPv4Network]:
    """Parse and sort CIDR strings into IPv4Network objects."""
    networks = [ipaddress.IPv4Network(cidr.strip()) for cidr in cidrs]
    return sorted(networks, key=lambda x: (x.network_address, x.prefixlen))

def merge_cidrs(cidrs: List[str]) -> List[str]:
    """Merge overlapping or consecutive CIDRs."""
    if not cidrs:
        return []

    # Parse and sort networks
    networks = parse_cidrs(cidrs)
    merged = []
    current = networks[0]

    for next_net in networks[1:]:
        # Check if networks can be merged
        if current.supernet_of(next_net):
            # Current network already contains next network, skip
            continue
        elif current.network_address + current.num_addresses == next_net.network_address:
            # Networks are consecutive, try to merge them
            try:
                # Attempt to create a supernet that contains both
                merged_net = ipaddress.IPv4Network(
                    f"{current.network_address}/{current.prefixlen - 1}"
                )
                if merged_net.network_address == current.network_address and \
                   merged_net.broadcast_address >= next_net.broadcast_address:
                    current = merged_net
                    continue
            except ValueError:
                pass
        elif current.overlaps(next_net):
            # Networks overlap, find the smallest network that contains both
            start = min(current.network_address, next_net.network_address)
            end = max(current.broadcast_address, next_net.broadcast_address)
            for prefix_len in range(current.max_prefixlen, -1, -1):
                try:
                    candidate = ipaddress.IPv4Network(
                        f"{start}/{prefix_len}", strict=False
                    )
                    if candidate.broadcast_address >= end:
                        current = candidate
                        break
                except ValueError:
                    continue
            continue

        # If we can't merge, add current to results and move to next
        merged.append(current)
        current = next_net

    # Add the last network
    merged.append(current)
    return [str(net) for net in merged]

def format_terraform_entries(cidrs: List[str]) -> str:
    """Format CIDRs as Terraform entry blocks."""
    return "\n".join(f'  entry {{\n    cidr        = "{cidr}"\n  }}' for cidr in cidrs)

def main():
    # Fetch AWS IP ranges for cn-northwest-1
    print("Fetching AWS IP ranges for cn-northwest-1 region...")
    aws_cidrs = fetch_aws_ip_ranges()

    if not aws_cidrs:
        print("No IP ranges found or error occurred.")
        return

    print(f"\nFound {len(aws_cidrs)} original CIDRs (sorted and deduplicated):")
    for cidr in aws_cidrs:
        print(cidr)

    print("\nMerging CIDRs...")
    merged = merge_cidrs(aws_cidrs)
    print(f"Merged into {len(merged)} CIDRs")

    print("\nTerraform format:")
    print(format_terraform_entries(merged))

if __name__ == "__main__":
    main()

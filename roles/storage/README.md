# Storage Role

This Ansible role manages storage configuration for the NAS, including ZFS pool/dataset management and RAID array setup.

## Features

- **ZFS Support**: Create and manage ZFS pools and datasets with custom properties
- **RAID Support**: Configure and mount RAID arrays (RAID 0, 1, 5, 6, 10)
- **Flexible Configuration**: Use encrypted variables (SOPS) for sensitive storage data

## Configuration

### ZFS Setup Example

Add to your inventory or group_vars:

```yaml
storage_zfs_enabled: true
storage_zfs_pools:
  - name: tank
    properties:
      ashift: "12"
      compression: "lz4"
      recordsize: "1M"

storage_zfs_datasets:
  - name: tank/data
    mountpoint: /data
    properties:
      compression: "lz4"
  - name: tank/media
    mountpoint: /media
    properties:
      compression: "lz4"
```

### RAID Setup Example

```yaml
storage_raid_enabled: true
storage_raid_arrays:
  - name: md0
    devices:
      - /dev/sda1
      - /dev/sdb1
    level: 1
    fstype: ext4
    mountpoint: /mnt/raid0
```

## Variables

- `storage_packages`: Packages to install (default: ZFS utilities)
- `storage_zfs_enabled`: Enable ZFS configuration (default: true)
- `storage_zfs_pools`: List of ZFS pools to create
- `storage_zfs_datasets`: List of ZFS datasets to create
- `storage_raid_enabled`: Enable RAID configuration (default: false)
- `storage_raid_arrays`: List of RAID arrays to create

## Encrypted Variables

Use SOPS to manage sensitive storage configuration:

```bash
sops roles/storage/vars/storage.sops.yaml
```

## Requirements

- Ansible >= 2.9
- community.general collection
- ansible.posix collection
- Python 3.6+
- For ZFS: Linux kernel with ZFS support
- For RAID: mdadm package

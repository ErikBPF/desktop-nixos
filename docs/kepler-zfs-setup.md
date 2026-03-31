# Kepler ZFS Pool Setup

ZFS pools are **not** managed by disko. They are created once imperatively and survive reprovisioning because nixos-anywhere only touches declared disko disks (the NVMe OS disk).

## Current disk inventory (verified on live ISO)

| Device | by-id | Size | Role |
|--------|-------|------|------|
| sdc | ata-TOSHIBA_KSG60ZMV256G_M.2_2280_256GB_58SF70G0F5WP | 238GB | OS (disko) |
| sda | ata-KINGSTON_SA400S37480G_50026B7783B0EBC7 | 480GB | fast-pool |
| sdb | ata-KINGSTON_SA400S37480G_50026B7783B0EB9E | 480GB | fast-pool |
| sdd | ata-KINGSTON_SA400S37480G_50026B7783B0EB50 | 480GB | fast-pool |
| sde | ata-KINGSTON_SA400S37480G_50026B7783B0EC7C | 480GB | fast-pool |
| HBA (LSI SAS3008, IT mode) | — | — | future bulk-pool (HDDs via SAS) |

Note: The M.2 slot is **SATA-only** on this board — there is no PCIe NVMe.
The SAS HBA is confirmed IT mode (`Protocol=(Initiator,Target)`, no RAID capabilities).

## Prerequisites

After nixos-anywhere completes and Kepler has booted into NixOS, SSH in and run these commands.

## 1. Identify disk IDs

```bash
ls -la /dev/disk/by-id/ | grep -v part
```

Map the output to disks. Example:
```
ata-Samsung_SSD_850_EVO_500GB_xxxx  -> /dev/sda  (fast pool)
ata-Samsung_SSD_850_EVO_500GB_yyyy  -> /dev/sdb  (fast pool)
ata-Samsung_SSD_850_EVO_500GB_zzzz  -> /dev/sdc  (fast pool)
ata-Samsung_SSD_850_EVO_500GB_wwww  -> /dev/sdd  (fast pool)
ata-WDC_WD40EZRX_aaaa               -> /dev/sde  (bulk pool)
ata-WDC_WD40EZRX_bbbb               -> /dev/sdf  (bulk pool)
ata-WDC_WD40EZRX_cccc               -> /dev/sdg  (bulk pool)
ata-WDC_WD40EZRX_dddd               -> /dev/sdh  (bulk pool)
ata-WDC_WD40EZRX_eeee               -> /dev/sdi  (bulk pool)
ata-CT240BX500SSD1_xxxx             -> /dev/sdj  (bulk L2ARC cache)
ata-CT240BX500SSD1_yyyy             -> /dev/sdk  (bulk L2ARC cache)
```

## 2. Create fast-pool (RAIDZ1, 4x Kingston 480GB SATA → ~1.4TB usable)

```bash
sudo zpool create \
  -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  fast-pool raidz1 \
  /dev/disk/by-id/ata-KINGSTON_SA400S37480G_50026B7783B0EBC7 \
  /dev/disk/by-id/ata-KINGSTON_SA400S37480G_50026B7783B0EB9E \
  /dev/disk/by-id/ata-KINGSTON_SA400S37480G_50026B7783B0EB50 \
  /dev/disk/by-id/ata-KINGSTON_SA400S37480G_50026B7783B0EC7C
```

Create dataset:
```bash
sudo zfs create -o mountpoint=/fast fast-pool/data
```

## 3. Create bulk-pool (RAIDZ1, 5x 4TB HDD → ~16TB usable) with L2ARC

```bash
sudo zpool create \
  -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  bulk-pool raidz1 \
  /dev/disk/by-id/ata-DISK_ID_HDD1 \
  /dev/disk/by-id/ata-DISK_ID_HDD2 \
  /dev/disk/by-id/ata-DISK_ID_HDD3 \
  /dev/disk/by-id/ata-DISK_ID_HDD4 \
  /dev/disk/by-id/ata-DISK_ID_HDD5
```

Add L2ARC (read cache) from the 2x 240GB SSDs:
```bash
sudo zpool add bulk-pool cache \
  /dev/disk/by-id/ata-DISK_ID_CACHE_SSD1 \
  /dev/disk/by-id/ata-DISK_ID_CACHE_SSD2
```

Create dataset:
```bash
sudo zfs create -o mountpoint=/bulk bulk-pool/data
```

## 4. Create subdirectory structure

```bash
# Fast pool — active models, scratch, AI workloads
sudo mkdir -p /fast/{models,scratch,datasets}
sudo chown -R erik:users /fast

# Bulk pool — cold storage, media, backups
sudo mkdir -p /bulk/{media,backups,archives}
sudo chown -R erik:users /bulk
```

## 5. Set hostId in default.nix

The `networking.hostId` in `modules/hosts/kepler/default.nix` must match this machine:

```bash
head -c 8 /etc/machine-id
```

Update `networking.hostId = "XXXXXXXX";` in the config and redeploy.

## 6. Set up Samba password

```bash
sudo smbpasswd -a erik
```

## 7. Verify

```bash
zpool status
zpool list
zfs list
df -h /fast /bulk
```

## Notes

- **L2ARC is a read cache only** — losing the cache SSDs does not lose data.
- **RAIDZ1 survives 1 disk failure per pool.** With 5 HDDs, losing 2 simultaneously means data loss on bulk-pool. This matches the stated tolerance ("bulk information is not super important to be kept").
- **Pool names must match** `boot.zfs.extraPools` in hardware.nix (`fast-pool`, `bulk-pool`).
- **Do not partition ZFS disks** — pass whole disks to zpool create. The `ashift=12` matches 4K sector alignment for modern drives.
- Scrub schedule is enabled by default via NixOS ZFS module (`services.zfs.autoScrub.enable = true` — set this in hardware.nix after first verified boot).

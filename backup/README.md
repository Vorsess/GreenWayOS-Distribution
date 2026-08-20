# GreenWayOS Backup Files

This folder contains backup and archived files that are not part of the active build process.

## Files

### greenwayos-installer-gui-modern
- **Type**: Python3 script (PyQt5)
- **Purpose**: Original modern PyQt5 GUI installer (standalone version)
- **Status**: ARCHIVED (superseded by main `greenwayos-installer-gui`)
- **Note**: This file was the reference implementation used to modernize the main installer

## Structure

- `/backup/` - Contains archived/backup files
- Not included in `./build.sh` or ISO generation
- Safe to delete if no longer needed

## Usage

If you need to restore or reference the modern installer template:
```bash
cp backup/greenwayos-installer-gui-modern config/includes.chroot/usr/local/bin/
```

---

**Created**: 2026-05-10  
**Project**: GreenWayOS 1.0 Installer Modernization

#!/usr/bin/env nu

let paths = [ 'Code' 'Documents' ]
let ssd = '/dev/disk/by-uuid/232823d5-ae5d-496c-a63c-ed1e4dbcd489'
let home = '/home/erik'

def get_key [] {
    match (hostname) {
        michael-desktop => '/dev/sdb',
        michael-laptop => '/dev/sda'
    }
}

def ssd_mount [] {
    sudo cryptsetup luksOpen -d (get_key) -l 4096 $ssd ssd; do { 
        mkdir $'($home)/SSD'
        sudo mount /dev/mapper/ssd $'($home)/SSD'
        sudo -u erik notify-send 'SSD is mounted.'
    }
}

def ssd_unmount [] {
    sudo umount $'($home)/SSD'; do {
        rmdir $'($home)/SSD'
        sudo cryptsetup luksClose ssd
        sudo -u erik notify-send 'SSD is safe to remove.'
    }
}

def ssd_sync [dir: string] {
    (sudo -u erik rclone bisync 
        --create-empty-src-dirs 
        --ignore-checksum 
        --ignore-listing-checksum 
        --exclude-from /home/erik/.config/exclude.list 
        --progress 
        $'($home)/($dir)' $'($home)/SSD/($dir)'
    )
    if $env.LAST_EXIT_CODE != 0 {
        sudo -u erik notify-send $'Error syncing ($dir)'
    }
}

ssd_mount
$paths | each { |p| ssd_sync $p }
ssd_unmount

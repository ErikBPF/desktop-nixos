alias s = sudo
alias nv = nvim
alias se = sudoedit
alias ze = zellij edit
alias bv = brave
alias icat = kitten icat

def "clean" [] {
    s -v
    s nix-collect-garbage --delete-older-than 7d
}

def "update" [] {
    nix flake update ~/Dots/ 
}

def "update full" [] {
    s -v
    update
    clean
    rebuild boot 
}             

def "rebuild" [cmd: string] {
    s -v
    sec dec
    s nixos-rebuild $cmd --flake $"($env.HOME)/Dots/" --impure
    sec rm
}

def "shell" [...pkgs: string] {
    let pkglist = ($pkgs | each { |p| $"nixpkgs#($p)" })
    nix shell -I ~/Dots ...$pkglist 
}

def "conf push" [m: string] {
    cd ~/Dots
    git stage -A
    git commit -m $m
    git push -u origin main
}

def "conf diff" [] {
    cd ~/Dots
    git diff @{upstream}
}

def "conf pull" [] {
    cd ~/Dots
    git reset --hard
    git pull --recurse-submodules
}

def "key" [] {
    let keyfile = match (hostname) {
        "michael-server" => "/dev/mmcblk0",
        _ => "/dev/sda",
    }
    s dd $"if=($keyfile)" bs=4096 count=1 status=none | openssl base64
}

def "sec enc" [] {
    s -v
    echo (key) | openssl aes-256-cbc -salt -pbkdf2 -e -in /tmp/secrets.toml -out ~/Dots/secrets -pass stdin
}

def "sec dec" [] {
    s -v
    echo (key) | openssl aes-256-cbc -salt -pbkdf2 -d -in ~/Dots/secrets -out /tmp/secrets.toml -pass stdin
}

def "sec rm" [] {
    rm -r /tmp/secrets.toml 
}

def "ssd" [] {
    s -v
    s cryptsetup luksOpen -d /dev/sdb -l 4096 /dev/disk/by-uuid/232823d5-ae5d-496c-a63c-ed1e4dbcd489 ssd
    if $env.LAST_EXIT_CODE == 0 {
        mkdir $"($env.HOME)/SSD"
        s mount /dev/mapper/ssd $"($env.HOME)/SSD"
   } else { sh -c false }
}

def "ssd rm" [] {
    s -v
    s umount $"($env.HOME)/SSD"
    if $env.LAST_EXIT_CODE == 0 {
        rmdir $"($env.HOME)/SSD"
        s fsck.f2fs /dev/mapper/ssd
        s cryptsetup luksClose ssd
    }
}

#!/nix/store/jnyfsf2mp08d1xyz2m72ic2vz2kcx0sd-bash-5.3p9/bin/sh

theme=Flat-Remix-GTK-White-Darkest

rm -rf ~/.config/gtk-4.0/gtk.css \
       ~/.config/gtk-4.0/assets \
       ~/.config/gtk-4.0/uninstall.sh \
       ~/.themes/$theme/

gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"

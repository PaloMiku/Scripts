#!/bin/bash

# if a password was set by decky, this will run when the program closes
temp_pass_cleanup() {
  echo $PASS | sudo -S -k passwd -d deck
}

# removes unhelpful GTK warnings
zen_nospam() {
  zenity 2> >(grep -v 'Gtk' >&2) "$@"
}

# check if JQ is installed
if ! command -v jq &> /dev/null
then
    echo "未找到 JQ，请先安装它"
    echo "要了解如何安装 JQ ，请参考 https://stedolan.github.io/jq/download/"
    exit 1
fi

# check if github.com is reachable
if ! curl -Is https://github.com | head -1 | grep 200 > /dev/null
then
    echo "无法正确连接到 Github，您可能未连接到互联网或配置正确的网络环境，这可能会导致安装失败。"
    exit 1
fi

# if the script is not root yet, get the password and rerun as root
if (( $EUID != 0 )); then
    PASS_STATUS=$(passwd -S deck 2> /dev/null)
    if [ "$PASS_STATUS" = "" ]; then
        echo "未找到 Deck 用户。您可以继续执行安装程序，这可能只是因为您在使用非 SteamOS 系统。"
    fi

    if [ "${PASS_STATUS:5:2}" = "NP" ]; then # if no password is set
        if ( zen_nospam --title="Decky Loader 安装程序" --width=300 --height=200 --question --text="您似乎尚未设置管理员密码。\n安装程序仍然可以通过临时将您的密码设置为 'Decky!' 并继续安装，在安装完成后则会将其移除。\n您确定是否要这样做吗？" ); then
            yes "Decky!" | passwd deck
            trap temp_pass_cleanup EXIT
            PASS="Decky!"
        else exit 1; fi
    else
        # get password
        FINISHED="false"
        while [ "$FINISHED" != "true" ]; do
            PASS=$(zen_nospam --title="Decky Loader 安装程序" --width=300 --height=100 --entry --hide-text --text="请输入您的 Sudo 管理员密码")
            if [[ $? -eq 1 ]] || [[ $? -eq 5 ]]; then
                exit 1
            fi
            if ( echo "$PASS" | sudo -S -k true ); then
                FINISHED="true"
            else
                zen_nospam --title="Decky Loader 安装程序" --width=150 --height=40 --info --text "密码错误"
            fi
        done
    fi

    if ! [ $USER = "deck" ]; then
        zen_nospam --title="Decky Loader 安装程序" --width=300 --height=100 --warning --text "您似乎并非在 Deck 用户下运行。\nDecky Loader 仍然可以正常工作，但某些功能可能无法完全使用。"
    fi
    
    echo "$PASS" | sudo -E -S -k bash "$0" "$@" # rerun script as root
    exit 1
fi

# all code below should be run as root
USER_DIR="$(getent passwd $SUDO_USER | cut -d: -f6)"
HOMEBREW_FOLDER="${USER_DIR}/homebrew"

# if decky is already installed, then add 'uninstall' and 'wipe' option
if [[ -f "${USER_DIR}/homebrew/services/PluginLoader" ]] ; then
    OPTION=$(zen_nospam --title="Decky Loader 安装程序" --width=750 --height=400 --list --radiolist --text "请选择您要执行的操作：" --hide-header --column "按钮" --column "选项" --column "说明" \
    TRUE "更新到最新正式版" "推荐用于稳定版 SteamOS" \
    FALSE "更新到最新预览版" "推荐用于 Beta/Preview 版 SteamOS" \
    FALSE "卸载 Decky Loader" "将会保留配置文件和安装过的插件" \
    FALSE "彻底删除 Decky Loader" "不会保留配置文件和安装过的插件")
else
    OPTION=$(zen_nospam --title="Decky Loader 安装程序" --width=750 --height=300 --list --radiolist --text "请选择您要安装的分支版本：" --hide-header --column "按钮" --column "选项" --column "说明" \
    TRUE "正式版" "推荐用于稳定版 SteamOS" \
    FALSE "预览版" "推荐用于 Beta/Preview 版 SteamOS")
fi

if [[ $? -eq 1 ]] || [[ $? -eq 5 ]]; then
    exit 1
fi

# uninstall if uninstall option was selected
if [[ "$OPTION" == "uninstall decky loader" || "$OPTION" == "wipe decky loader" ]] ; then
    (
    echo "20" ; echo "# Disabling and removing services" ;
    sudo systemctl disable --now plugin_loader.service > /dev/null
    sudo rm -f "${USER_DIR}/.config/systemd/user/plugin_loader.service"
    sudo rm -f "/etc/systemd/system/plugin_loader.service"

    echo "40" ; echo "# Removing Temporary Files" ;
    rm -rf "/tmp/plugin_loader"
    rm -rf "/tmp/user_install_script.sh"

    if [ "$OPTION" == "wipe decky loader" ]; then
        echo "60" ; echo "# Deleting homebrew folder" ;
        sudo rm -r "${HOMEBREW_FOLDER}"
    else
        echo "60" ; echo "# Cleaning services folder" ;
        sudo rm "${HOMEBREW_FOLDER}/services/PluginLoader"
    fi

    echo "80" ; echo "# Disabling CEF debugging" ;
    sudo rm "${USER_DIR}/.steam/steam/.cef-enable-remote-debugging"
    sudo rm "${USER_DIR}/.var/app/com.valvesoftware.Steam/data/Steam/.cef-enable-remote-debugging" 2> /dev/null

    echo "100" ; echo "# Uninstall finished, installer can now be closed";
    ) |
    zen_nospam --progress \
  --title="Decky Loader 安装程序" \
  --width=300 --height=100 \
  --text="卸载中..." \
  --percentage=0 \
  --no-cancel
  exit 0
fi

# otherwise, install decky
if [[ "$OPTION" =~ "pre" ]]; then
    BRANCH="prerelease"
else
    BRANCH="release"
fi

(
echo "15" ; echo "# Creating file structure" ;
rm -rf "${HOMEBREW_FOLDER}/services"
sudo -u $SUDO_USER  mkdir -p "${HOMEBREW_FOLDER}/services"
sudo -u $SUDO_USER  mkdir -p "${HOMEBREW_FOLDER}/plugins"
sudo -u $SUDO_USER  touch "${USER_DIR}/.steam/steam/.cef-enable-remote-debugging"
# if installed as flatpak, put .cef-enable-remote-debugging there
[ -d "${USER_DIR}/.var/app/com.valvesoftware.Steam/data/Steam/" ] && sudo -u $SUDO_USER touch "${USER_DIR}/.var/app/com.valvesoftware.Steam/data/Steam/.cef-enable-remote-debugging"

echo "30" ; echo "# Finding latest $BRANCH";
if [ "$BRANCH" = 'prerelease' ] ; then
    RELEASE=$(curl -s 'https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases' | jq -r "first(.[] | select(.prerelease == "true"))")
else
    RELEASE=$(curl -s 'https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases' | jq -r "first(.[] | select(.prerelease == "false"))")
fi
VERSION=$(jq -r '.tag_name' <<< ${RELEASE} )
DOWNLOADURL=$(jq -r '.assets[].browser_download_url | select(endswith("PluginLoader"))' <<< ${RELEASE})

echo "45" ; echo "# Installing version $VERSION" ;
# make another zenity prompt while downloading the PluginLoader file, I do not know how this works
curl -L $DOWNLOADURL -o ${HOMEBREW_FOLDER}/services/PluginLoader 2>&1 | stdbuf -oL tr '\r' '\n' | sed -u 's/^ *\([0-9][0-9]*\).*\( [0-9].*$\)/\1\n#Download Speed\:\2/' | zen_nospam --progress --title "下载 Decky Loader" --text="Download Speed: 0" --width=300 --height=100 --auto-close --no-cancel
chmod +x ${HOMEBREW_FOLDER}/services/PluginLoader

echo "60"; echo "Running SELinux fix if it is enabled"
hash getenforce 2>/dev/null && getenforce | grep "Enforcing" >/dev/null && chcon -t bin_t ${HOMEBREW_FOLDER}/services/PluginLoader

echo $VERSION > ${HOMEBREW_FOLDER}/services/.loader.version

echo "70" ; echo "# Killing plugin_loader if it exists" ;
systemctl --user stop plugin_loader 2> /dev/null
systemctl --user disable plugin_loader 2> /dev/null
systemctl stop plugin_loader 2> /dev/null
systemctl disable plugin_loader 2> /dev/null

echo "85" ; echo "# Setting up systemd" ;
curl -L https://raw.githubusercontent.com/SteamDeckHomebrew/decky-loader/main/dist/plugin_loader-${BRANCH}.service  --output ${HOMEBREW_FOLDER}/services/plugin_loader-${BRANCH}.service
cat > "${HOMEBREW_FOLDER}/services/plugin_loader-backup.service" <<- EOM
[Unit]
Description=SteamDeck Plugin Loader
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
Restart=always
ExecStart=${HOMEBREW_FOLDER}/services/PluginLoader
WorkingDirectory=${HOMEBREW_FOLDER}/services
KillSignal=SIGKILL
Environment=PLUGIN_PATH=${HOMEBREW_FOLDER}/plugins
Environment=LOG_LEVEL=INFO
[Install]
WantedBy=multi-user.target
EOM

# if .service file doesn't exist for whatever reason, use backup file instead
if [[ -f "${HOMEBREW_FOLDER}/services/plugin_loader-${BRANCH}.service" ]]; then
    printf "Grabbed latest ${BRANCH} service.\n"
    sed -i -e "s|\${HOMEBREW_FOLDER}|${HOMEBREW_FOLDER}|" "${HOMEBREW_FOLDER}/services/plugin_loader-${BRANCH}.service"
    cp -f "${HOMEBREW_FOLDER}/services/plugin_loader-${BRANCH}.service" "/etc/systemd/system/plugin_loader.service"
else
    printf "Could not curl latest ${BRANCH} systemd service, using built-in service as a backup!\n"
    rm -f "/etc/systemd/system/plugin_loader.service"
    cp "${HOMEBREW_FOLDER}/services/plugin_loader-backup.service" "/etc/systemd/system/plugin_loader.service"
fi

mkdir -p ${HOMEBREW_FOLDER}/services/.systemd
cp ${HOMEBREW_FOLDER}/services/plugin_loader-${BRANCH}.service ${HOMEBREW_FOLDER}/services/.systemd/plugin_loader-${BRANCH}.service
cp ${HOMEBREW_FOLDER}/services/plugin_loader-backup.service ${HOMEBREW_FOLDER}/services/.systemd/plugin_loader-backup.service
rm ${HOMEBREW_FOLDER}/services/plugin_loader-backup.service ${HOMEBREW_FOLDER}/services/plugin_loader-${BRANCH}.service

systemctl daemon-reload
systemctl start plugin_loader
systemctl enable plugin_loader

# this (retroactively) fixes a bug where users who ran the installer would have homebrew owned by root instead of their user
# will likely be removed at some point in the future
if [ "$SUDO_USER" =  "deck" ]; then
  sudo chown -R deck:deck "${HOMEBREW_FOLDER}"
  sudo chown -R root:root "${HOMEBREW_FOLDER}"/services/*
fi

echo "100" ; echo "# Install finished, installer can now be closed";
) |
zen_nospam --progress \
  --title="Decky Loader 安装程序" \
  --width=300 --height=100 \
  --text="安装中..." \
  --percentage=0 \
  --no-cancel # not actually sure how to make the cancel work properly, so it's just not there unless someone else can figure it out

if [ "$?" = -1 ] ; then
        zen_nospam --title="Decky Loader 安装程序" --width=150 --height=70 --error --text="Download interrupted."
fi

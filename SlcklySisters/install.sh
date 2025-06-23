#!/bin/bash

PROJECT_NAME="《痴情哥哥与病弱妹妹的乡间生活》"

DOWNLOAD_URL="https://www.vnwiki.xyz/dlls/d2d1.dll"

FILENAME="d2d1.dll"

INSTALL_DIR_DEFAULT="/home/$USER/.local/"

zen_nospam() {
  zenity 2> >(grep -v 'Gtk' >&2) "$@"
}

if ! zen_nospam --question --title="$PROJECT_NAME Wine 运行补丁安装程序" --width=500 --text="欢迎使用 $PROJECT_NAME Wine 补丁安装程序。\n\n注意：本安装程序并非游戏开发商或发行商提供 \n\n此脚本将从 VnWiki 下载补丁文件并将其安装到游戏目录中。\n\n请在下一个弹出窗口选择您的游戏本地存储目录。 \n\n请问是否继续下载安装？"; then
    exit 0
fi


INSTALL_DIR=$(zen_nospam --file-selection --directory --title="请选择安装目录" --filename="${INSTALL_DIR_DEFAULT}/")
if [ $? -ne 0 ]; then
    exit 0
fi


if ! zen_nospam --question --title="最终确认" --text="文件将被安装到:\n\n<b>${INSTALL_DIR}/${FILENAME}</b>\n\n确定吗？"; then
    exit 0
fi


TMP_DIR=$(mktemp -d)


if ! curl -L "$DOWNLOAD_URL" -o "$TMP_DIR/$FILENAME" ; then
    zen_nospam --error --text="下载失败。请检查 URL 和您的网络连接。"
    rm -rf "$TMP_DIR"
    exit 1
fi


if ! mkdir -p "$INSTALL_DIR" ; then
    zen_nospam --error --text="无法创建目录 '$INSTALL_DIR'。请检查权限。"
    rm -rf "$TMP_DIR"
    exit 1
fi

if ! mv "$TMP_DIR/$FILENAME" "$INSTALL_DIR/$FILENAME" ; then
    zen_nospam --error --text="安装失败！请检查 '$INSTALL_DIR' 的写入权限。"
    rm -rf "$TMP_DIR"
    exit 1
fi

chmod +x "$INSTALL_DIR/$FILENAME"
rm -rf "$TMP_DIR"


if [ -f "$INSTALL_DIR/$FILENAME" ]; then
    zen_nospam --info --title="安装成功" --width=500 --text="游戏补丁已成功安装到:\n\n<b>$INSTALL_DIR/$FILENAME</b>\n\n请在 Steam 游戏属性中添加额外环境变量以应用此补丁：WINEDLLOVERRIDES="d2d1.dll=n,b" %command%"
else
    zen_nospam --error --title="安装失败" --text="安装过程中发生未知错误。请查看终端输出以获取详细信息。"
fi

exit 0

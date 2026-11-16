// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 QueMusic Contributors
//
// 歌曲收藏夹选择：全应用共用一份，各收藏按钮调 Options.favPicker.show(item)。
// 下半部分「平台歌单」需要登录 + 平台支持写入（目前只有网易云），把歌直接存进账号歌单。
pragma ComponentBehavior: Bound
import QtQuick
import QueMusic 1.0

QOptionDialog {
    id: root
    title: "收藏到"
    cancelText: "取消收藏"
    cancelIcon: "\uf025"
    confirmText: "完成"
    headerHeight: 24
    property var item
    property string pendingTarget: ""   // 正在添加到的平台歌单名，用于回执提示

    // 这个平台能不能写歌单（同时要求已登录）。
    // 顺手读一个登录态属性，让登录/退出后能重新求值（invokable 本身不带 NOTIFY）。
    readonly property bool canWrite: {
        const _login = AccountManager.neteaseLoggedIn
        return !!item && MusicApi.canWritePlaylists(item.source !== undefined ? item.source : -1)
    }

    function show(song: var): void {
        item = song
        pendingTarget = ""
        // 平台歌单列表和「我的」页共用一个模型：空的话顺手拉一页
        if (canWrite && MusicApi.userPlaylists.count === 0 && !MusicApi.loadState)
            MusicApi.getUserPlaylists(1, 50, item.source)
        open()
    }

    // 取消收藏：收藏过就撤掉，没收藏就不管
    onCancel: {
        if (root.item && FavoriteSongs.isFavorite(root.item.id, "song")) {
            FavoriteSongs.removeFavorite(root.item.id, "song")
            Options.warned("已取消收藏", 0)
        }
    }

    // 写入结果（playlistAddSong / playlistRemoveSong / playlistCreate）统一走这里弹提示
    Connections {
        target: MusicApi
        function onActionFinished(action: string, ok: bool, message: string): void {
            if (action === "playlistAddSong" && ok && root.pendingTarget !== "")
                Options.warned("已添加到「" + root.pendingTarget + "」", 1)
            else
                Options.warned(message, ok ? 1 : 0)
            root.pendingTarget = ""
        }
    }

    options: Column {
        width: root.width - 40
        spacing: 4

        // ── 本地收藏夹 ──────────────────────────────────────────────
        Repeater {
            model: FavoriteFolders
            delegate: Rectangle {
                id: folderRow
                required property int folderId
                required property string name
                required property bool isDefault
                width: parent.width
                height: 48
                radius: Style.labelRadius
                color: folderArea.containsMouse ? Theme.hoverColor : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 14
                    text: "\uf0f5"
                    font.family: Fonts.icon
                    font.pixelSize: Style.texticon
                    color: Theme.textColor
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 52
                    width: parent.width - 66
                    text: folderRow.name
                    color: Theme.fontColor
                    font.pixelSize: Style.textmain
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: folderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (!root.item)
                            return
                        FavoriteSongs.addToFolder(root.item.id, root.item.title, root.item.artist,
                                                  root.item.cover, root.item.source,
                                                  root.item.duration || 0, folderRow.folderId)
                        Options.warned("已收藏到「" + folderRow.name + "」", 1)
                        root.close()
                    }
                }
            }
        }
        Text {
            visible: FavoriteFolders.count === 0
            width: parent.width
            height: 48
            text: "暂无收藏夹"
            color: Theme.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // ── 平台歌单（写回账号，不是本地收藏）─────────────────────────
        Rectangle {
            visible: root.canWrite
            width: parent.width
            height: 1
            color: Theme.sideColor
        }
        Item {
            visible: root.canWrite
            width: parent.width
            height: visible ? 30 : 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 4
                text: "平台歌单（" + MusicApi.sourceNameOf(root.item ? root.item.source : -1) + "）"
                color: Theme.textColor
                font.pixelSize: Style.textTip
                font.weight: Font.DemiBold
            }
        }
        Repeater {
            model: root.canWrite ? MusicApi.userPlaylists : null
            delegate: Rectangle {
                id: platformRow
                required property string title
                required property string hash
                required property real duration
                width: parent.width
                height: 48
                radius: Style.labelRadius
                color: platformArea.containsMouse ? Theme.hoverColor : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 14
                    text: "\uf055"
                    font.family: Fonts.icon
                    font.pixelSize: Style.texticon
                    color: Theme.textColor
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 52
                    width: parent.width - 140
                    text: platformRow.title
                    color: Theme.fontColor
                    font.pixelSize: Style.textmain
                    elide: Text.ElideRight
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    text: platformRow.duration + " 首"
                    color: Theme.textColor
                    font.pixelSize: Style.textTip
                }
                MouseArea {
                    id: platformArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (!root.item)
                            return
                        // 不关弹窗：可以连续加到多个歌单；结果由 onActionFinished 提示
                        root.pendingTarget = platformRow.title
                        MusicApi.playlistAddSong(platformRow.hash, root.item.id, root.item.source)
                    }
                }
            }
        }
        Text {
            visible: root.canWrite && MusicApi.userPlaylists.count === 0
            width: parent.width
            height: 44
            text: MusicApi.loadState ? "读取歌单中…" : "账号里还没有歌单，可以先去「我的」页看一眼"
            color: Theme.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Style.textTip
        }
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025-2026 QueMusic Contributors
//
// 「我的」：账号在音乐平台侧的歌单与「我喜欢的音乐」。
//
// 数据全部来自 api/ 的账号类 action（getUserPlaylists / getUserFavoriteSongs），
// 由各平台实现读取，QML 只消费 OnlineListModel：
//   我的歌单     -> MusicApi.userPlaylists（每行 hash 就是平台歌单 id）
//   我喜欢的音乐 -> MusicApi.userFavoriteSongs
// 这里只读：在 QueMusic 本地收藏的内容不会写回平台账号。
//
// 注意：账号平台的歌单行本身不带 source 字段，行内「收藏」按钮会按当前音源
// （MusicApi.songSource）落库；当当前音源和登录平台不是同一个时，从收藏夹
// 打开该歌单需要用同一平台播放，这是 QListView.sourceOf() 的既有约定。
pragma ComponentBehavior: Bound
import QtQuick
import QueMusic 1.0

Item {
    id: myPage

    readonly property int pageSize: 20
    // 账号平台：优先当前音源；当前音源没登录时退到第一个已登录的平台
    readonly property int accountSource: {
        if (loggedIn(MusicApi.songSource))
            return MusicApi.songSource;
        for (let i = 0; i < 6; ++i) {
            if (loggedIn(i))
                return i;
        }
        // 脚本音源（>= 100）没有账号体系，退回酷狗，至少给一个能登录的提示
        return MusicApi.songSource >= 0 && MusicApi.songSource < 6 ? MusicApi.songSource : 0;
    }
    readonly property bool accountReady: loggedIn(accountSource)
    readonly property string accountName: MusicApi.sourceNameOf(accountSource)
    readonly property int requestGap: 1200     // 同一页的重复请求间隔（ms）
    property double playlistRequestAt: 0
    property double favoriteRequestAt: 0
    property int tabIndex: 0

    // 平台登录态：下标与 api/ApiActions.h 的 ApiSource 一致
    function loggedIn(source: int): bool {
        switch (source) {
        case 0: return AccountManager.kugouLoggedIn;
        case 1: return AccountManager.neteaseLoggedIn;
        case 2: return AccountManager.bilibiliLoggedIn;
        case 3: return AccountManager.qqLoggedIn;
        case 4: return AccountManager.spotifyLoggedIn;
        case 5: return AccountManager.appleLoggedIn;
        }
        return false;
    }

    function clearModels(): void {
        MusicApi.userPlaylists.clear();
        MusicApi.userFavoriteSongs.clear();
    }

    // 按需拉第一页；force = 清空重拉
    function ensureTab(index: int, force: bool): void {
        if (!accountReady)
            return;
        const now = Date.now();
        if (index === 0) {
            if (!force && MusicApi.userPlaylists.count > 0)
                return;
            // 快速来回切页会在同一页连发两次，结果会被追加两遍
            if (!force && now - playlistRequestAt < requestGap)
                return;
            playlistRequestAt = now;
            MusicApi.userPlaylists.clear();
            MusicApi.getUserPlaylists(1, pageSize, accountSource);
        } else if (index === 1) {
            if (!force && MusicApi.userFavoriteSongs.count > 0)
                return;
            if (!force && now - favoriteRequestAt < requestGap)
                return;
            favoriteRequestAt = now;
            MusicApi.userFavoriteSongs.clear();
            MusicApi.getUserFavoriteSongs(1, pageSize, accountSource);
        }
    }

    function refresh(): void {
        if (!accountReady) {
            Options.warned("请先在设置里登录" + accountName, 2);
            return;
        }
        ensureTab(tabIndex, true);
        Options.warned("正在读取" + accountName + "的" + (tabIndex === 0 ? "歌单" : "喜欢的音乐"), 0);
    }

    // 打开账号歌单：曲目灌进 MusicApi.playlistSong，由 PlayListWindow 展示
    function openPlaylist(item: var): void {
        if (!item || !item.hash)
            return;
        MusicApi.playlistSong.clear();
        MusicApi.getPlaylistSongs(item.hash, 1, pageSize, accountSource);
        songWindow.songSource = accountSource;
        songWindow.opened(item);
        Options.exitIndex = 1;
    }

    // 子窗口滚动到底：按已加载条数翻页
    function loadSongPage(): void {
        const loaded = MusicApi.playlistSong.count;
        if (loaded === 0 || loaded % pageSize !== 0)
            return;
        MusicApi.getPlaylistSongs(songWindow.id, loaded / pageSize + 1, pageSize,
                                  songWindow.songSource);
    }

    // 账号平台换了（登录 / 退出 / 切音源）：旧数据作废，重读当前页。
    // accountSource 与 accountReady 常常同一轮一起变，用 0ms 定时器合并成一次。
    Timer {
        id: reloadTimer
        interval: 0
        repeat: false
        onTriggered: {
            myPage.clearModels();
            myPage.ensureTab(myPage.tabIndex, false);
        }
    }
    onAccountSourceChanged: reloadTimer.restart()
    onAccountReadyChanged: reloadTimer.restart()
    Component.onCompleted: ensureTab(tabIndex, false)

    QPages {
        id: myTabs
        x: 24
        y: 68
        width: parent.width - 48
        height: parent.height - 68
        pageList: [playlistPage, favoritePage]

        // 顶部常驻标题
        Item {
            x: 0
            y: -44
            height: 40
            width: myTabs.width
            z: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "我的音乐"
                font.weight: Font.DemiBold
                font.pixelSize: Style.pageTitle
                color: Theme.fontColor
            }
        }

        QBlurTapBar {
            x: 0
            y: 12
            z: 5
            model: ["我的歌单", "我喜欢的音乐"]
            tabWidth: 104
            width: 214
            rectXy: Qt.rect(0, 12, width, 40)
            blurSource: myTabs.pageList[myTabs.lastIndex]
            onTabChange: (index) => {
                myPage.tabIndex = index;
                myTabs.stack(index);
                myPage.ensureTab(index, false);
            }
        }

        // 右侧：当前账号平台 / 刷新 / 去登录
        Row {
            x: parent.width - width
            y: 13
            z: 2
            spacing: 8
            Text {
                height: 38
                text: myPage.accountReady ? myPage.accountName + " · 只读" : "未登录"
                color: Theme.textColor
                font.pixelSize: Style.textmain
                verticalAlignment: Text.AlignVCenter
            }
            QButton {
                visible: myPage.accountReady
                height: 38
                text: "刷新"
                iconCharacter: "\uf10c"
                buttonColor: Theme.primaryColor
                tipText: "重新读取账号数据"
                onClicked: myPage.refresh()
            }
            QButton {
                visible: !myPage.accountReady
                height: 38
                text: "去登录"
                iconCharacter: "\uf055"
                buttonColor: Theme.themeColor
                textColor: Theme.fullColor
                iconColor: Theme.fullColor
                tipText: "在设置里登录" + myPage.accountName
                onClicked: {
                    if (Options.openSettings)
                        Options.openSettings();
                    else
                        Options.warned("请在设置 → 音源账号 中登录", 1);
                }
            }
        }

        // 我的歌单
        Item {
            id: playlistPage
            width: myTabs.width
            height: myTabs.height

            QListView {
                id: playlistView
                width: myTabs.width + 16
                height: myTabs.height
                model: MusicApi.userPlaylists
                clip: true
                isList: true
                topMargin: 72
                onClicked: (index) => myPage.openPlaylist(model.get(index))
                onEnded: {
                    const loaded = MusicApi.userPlaylists.count;
                    if (loaded === 0 || loaded % myPage.pageSize !== 0) {
                        isEnd = true;
                        return;
                    }
                    isEnd = false;
                    MusicApi.getUserPlaylists(loaded / myPage.pageSize + 1, myPage.pageSize,
                                              myPage.accountSource);
                }
                AnimatedImage {
                    anchors.centerIn: parent
                    visible: MusicApi.loadState && MusicApi.userPlaylists.count === 0
                    playing: visible
                    source: "qrc:/QueMusic/resources/loader.gif"
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: !MusicApi.loadState && MusicApi.userPlaylists.count === 0
                    text: myPage.accountReady
                          ? "账号里还没有歌单"
                          : "还没有登录" + myPage.accountName + "，登录后可在这里看到账号的歌单"
                    color: Theme.textColor
                    font.pixelSize: 14
                }
            }
        }

        // 我喜欢的音乐
        Item {
            id: favoritePage
            visible: false
            width: myTabs.width
            height: myTabs.height

            QListView {
                id: favoriteView
                width: myTabs.width + 16
                height: myTabs.height
                model: MusicApi.userFavoriteSongs
                clip: true
                topMargin: 72
                onClicked: (index) => MusicApi.playSong(model.get(index), myPage.accountSource)
                onEnded: {
                    const loaded = MusicApi.userFavoriteSongs.count;
                    if (loaded === 0 || loaded % myPage.pageSize !== 0) {
                        isEnd = true;
                        return;
                    }
                    isEnd = false;
                    MusicApi.getUserFavoriteSongs(loaded / myPage.pageSize + 1, myPage.pageSize,
                                                  myPage.accountSource);
                }
                AnimatedImage {
                    anchors.centerIn: parent
                    visible: MusicApi.loadState && MusicApi.userFavoriteSongs.count === 0
                    playing: visible
                    source: "qrc:/QueMusic/resources/loader.gif"
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: !MusicApi.loadState && MusicApi.userFavoriteSongs.count === 0
                    text: myPage.accountReady
                          ? "账号里还没有喜欢的音乐"
                          : "还没有登录" + myPage.accountName + "，登录后可在这里看到「我喜欢的音乐」"
                    color: Theme.textColor
                    font.pixelSize: 14
                }
            }
        }
    }

    // 歌单曲目：与收藏页同款滑出窗口
    PlayListWindow {
        id: songWindow
        mainTarget: myTabs
        winIndex: 1
        content: Item {
            QListView {
                x: 24
                y: 170
                width: songWindow.width - 32
                height: songWindow.height - 170
                model: MusicApi.playlistSong
                clip: true
                topMargin: 8
                bottomMargin: 24
                onClicked: (index) => MusicApi.playSong(model.get(index), songWindow.songSource)
                onEnded: myPage.loadSongPage()
            }
        }
    }
}

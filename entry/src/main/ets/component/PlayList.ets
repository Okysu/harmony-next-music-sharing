import { SongListCard } from './SongListCard';
import { TrackAndPrivilege } from '../type/Playlist';
import { globalPlaylist, PlaylistChangeType } from '../common/GlobalPlayListManager';
import { EventBus } from '../common/EventBus';
import { cover, isTrackPlayableWithParams } from '../common/APIHelper';
import { promptAction } from '@kit.ArkUI';
import { LazyData } from '@pie/lazy-data';

@Component
export struct PlayList {
  @Link showPlaylist: boolean;
  dataSource: LazyData<TrackAndPrivilege> = new LazyData();
  @StorageLink("Track") track: TrackAndPrivilege | null = null;
  @State isLoading: boolean = false;
  @State currentPage: number = 0;
  private readonly PAGE_SIZE: number = 50;
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    this.updatePlaylist();

    EventBus.listen<PlaylistChangeType>('PlayListChange', (type) => {
      switch (type) {
        case PlaylistChangeType.MOVE:
        case PlaylistChangeType.OVERWRITE:
        case PlaylistChangeType.CLEAR:
          this.updatePlaylist();
          break;
      }
    });
  }

  private updatePlaylist() {
    const fullList = globalPlaylist.getPlaylist();
    this.currentPage = 0;
    this.dataSource = new LazyData();

    // Load initial page
    const initialItems = fullList.slice(0, this.PAGE_SIZE);
    if (initialItems.length > 0) {
      this.dataSource.setData(initialItems);
      this.currentPage = 1;
    }
  }

  private loadMoreData() {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    try {
      const fullList = globalPlaylist.getPlaylist();
      const startIndex = this.currentPage * this.PAGE_SIZE;
      const endIndex = Math.min(startIndex + this.PAGE_SIZE, fullList.length);

      if (startIndex >= fullList.length) {
        return;
      }

      const newItems = fullList.slice(startIndex, endIndex);
      newItems.forEach(item => {
        this.dataSource.pushData(item);
      });

      this.currentPage++;
    } finally {
      this.isLoading = false;
    }
  }

  private handleDelete(track: TrackAndPrivilege) {
    if (track.track.id) {
      // Find the index in LazyData
      const localIndex = this.dataSource.getDataIndex((item: TrackAndPrivilege) =>
      item.track.id === track.track.id
      );

      // Get global index for determining current playing track position
      const globalCurrentIndex = globalPlaylist.getCurrentIndex();
      const globalTrackIndex = globalPlaylist.getPlaylist()
        .findIndex(item => item.track.id === track.track.id);

      if (localIndex !== -1) {
        // First delete from LazyData
        this.dataSource.deleteData(localIndex);

        // If deleting current playing track or track before it,
        // we need to adjust the current index
        if (globalTrackIndex <= globalCurrentIndex) {
          // Save current track to restore after deletion
          const currentTrack = globalPlaylist.getPlaylist()[globalCurrentIndex];

          // Delete from global playlist
          globalPlaylist.removeSong(track.track.id);

          // Find the new index of current track
          const newIndex = globalPlaylist.getPlaylist()
            .findIndex(item => item.track.id === currentTrack.track.id);

          // Set the current index back to maintain the playing track
          if (newIndex !== -1 && newIndex !== globalCurrentIndex) {
            globalPlaylist.setCurrentIndex(newIndex);
          }
        } else {
          // If deleting a track after current playing track,
          // we can just remove it without index adjustment
          globalPlaylist.removeSong(track.track.id);
        }
      }
    }
  }

  @Builder
  DeleteButton(track: TrackAndPrivilege) {
    Button() {
      Row() {
        Image($r('app.media.ic_trash'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
    }
    .width(48)
    .height(48)
    .backgroundColor($r('app.color.delete_button_bg'))
    .margin({ right: 16 })
    .onClick(() => {
      this.handleDelete(track);
    })
  }

  @Builder
  LoadingRow() {
    Row() {
      LoadingProgress()
        .width(24)
        .height(24)
        .color($r('app.color.loading_color'))
      Text('加载中...')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding(16)
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('当前播放列表')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Button() {
          Image($r('app.media.ic_close'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.icon_color'))
        }
        .width(36)
        .height(36)
        .type(ButtonType.Circle)
        .backgroundColor($r('app.color.playlist_close_button_bg'))
        .onClick(() => {
          this.showPlaylist = false;
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.playlist_bg'))

      // List
      List({ space: 4, scroller: this.scroller }) {
        LazyForEach(this.dataSource, (track: TrackAndPrivilege) => {
          ListItem() {
            SongListCard({
              title: track.track.name,
              tns: track.track.tns,
              artist: track.track.ar,
              index: globalPlaylist.getPlaylist().findIndex(item => item.track.id === track.track.id),
              coverUrl: cover(track.track.al?.picUrl ?? "", 64),
              active: this.track?.track.id === track.track.id,
              disabled: !isTrackPlayableWithParams(track.track, track.privilege).isPlayable,
              showIndex: false,
            })
              .onClick(() => {
                const playableResult = isTrackPlayableWithParams(track.track, track.privilege);
                if (!playableResult.isPlayable) {
                  promptAction.showToast({ message: playableResult.reason })
                  return
                }
                const globalIndex = globalPlaylist.getPlaylist()
                  .findIndex(item => item.track.id === track.track.id);
                if (globalIndex !== -1) {
                  globalPlaylist.setCurrentSongIndex(globalIndex);
                }
              })
          }
          .reuseId('playlist')
          .swipeAction({ end: this.DeleteButton(track) })
          .animation({
            duration: 300,
            curve: Curve.EaseInOut
          })
        }, (track: TrackAndPrivilege) => track.track.id.toString())

        // Loading indicator at the bottom
        if (this.currentPage * this.PAGE_SIZE < globalPlaylist.getPlaylist().length) {
          ListItem() {
            this.LoadingRow()
          }
        }
      }
      .cachedCount(3)
      .width('100%')
      .layoutWeight(1)
      .listDirection(Axis.Vertical)
      .margin({ top: 8 })
      .scrollBar(BarState.Off)
      .onReachEnd(() => {
        this.loadMoreData();
      })
    }
    .width('100%')
    .height('100%')
  }
}
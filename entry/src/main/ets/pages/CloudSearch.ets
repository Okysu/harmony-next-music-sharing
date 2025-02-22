import { promptAction, router } from '@kit.ArkUI'
import { SongListCard } from '../component/SongListCard'
import { SongDetail } from '../type/Song'
import { cloudSearch as search, suggest } from "../api/Search"
import { globalPlaylist } from '../common/GlobalPlayListManager'
import { TrackAndPrivilege, Track, Privilege, Playlist } from '../type/Playlist'
import { Artist } from '../type/Toplist'
import { cover, isTrackPlayableWithParams } from '../common/APIHelper'
import { PlaylistSelector } from '../component/PlaylistSelector'
import { collectSong } from '../api/Song'
import { PlaylistCard } from '../component/PlayListCard'
import { SearchSuggest, SearchSuggestResponse } from '../type/Search'

enum SearchType {
  SINGLE = 1,
  PLAYLIST = 1000
}

interface TabItem {
  name: string
  type: SearchType
}

@Entry
@Component
struct CloudSearch {
  @State searchText: string = ''
  @State searchResults: SongDetail[] = []
  @State playlistResults: Playlist[] = []
  @State isLoading: boolean = false
  @State isLoadingMore: boolean = false
  @State showResults: boolean = false
  @State currentTab: number = 0
  @State offsetValue: number = 0
  @State hasMore: boolean = true
  @State suggestions: SearchSuggest[] = []
  @State animationState: number = 0
  private readonly pageSize: number = 20
  private searchController: SearchController = new SearchController()
  @StorageLink("Track") track: TrackAndPrivilege | null = null
  @State showPlayListSelector: boolean = false
  private nowSelected: number | string = 0
  private debounceTimer: number | null = null
  private tabs: TabItem[] = [
    { name: '单曲', type: SearchType.SINGLE },
    { name: '歌单', type: SearchType.PLAYLIST }
  ]

  private ignoreNextSuggestions: boolean = false

  // 防抖函数实现
  private debounce(fn: Function, delay: number = 300) {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer)
    }
    this.debounceTimer = setTimeout(() => {
      fn()
      this.debounceTimer = null
    }, delay)
  }

  // 获取搜索建议
  private async fetchSuggestions(keywords: string) {

    if (this.ignoreNextSuggestions) {
      this.ignoreNextSuggestions = false
      return
    }

    if (!keywords.trim()) {
      animateTo({ duration: 200 }, () => {
        this.suggestions = []
        this.animationState = 0
      })
      return
    }

    try {
      const result = await suggest(keywords)
      if (result?.result?.allMatch) {
        animateTo({ duration: 200 }, () => {
          this.suggestions = result.result.allMatch.slice(0, 5)
          this.animationState = 1
        })
      } else {
        animateTo({ duration: 200 }, () => {
          this.suggestions = []
          this.animationState = 0
        })
      }
    } catch (error) {
      console.error('Failed to fetch suggestions:', error)
      this.suggestions = []
    }
  }

  @Builder
  PlayList() {
    Column() {
      PlaylistSelector({
        onSelect: async (id: string | number) => {
          await collectSong(id, [this.nowSelected])
          promptAction.showToast({ message: "已添加到收藏夹" })
          this.showPlayListSelector = false;
        }
      })
    }
    .expandSafeArea()
    .height("100%")
    .backgroundColor($r('app.color.playlist_bg'))
    .layoutWeight(1)
  }

  @Builder
  MoreActions(track: SongDetail) {
    Button({ type: ButtonType.Circle }) {
      Image($r('app.media.ic_more'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.icon_color'))
    }
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .bindMenu([
      {
        value: '添加到下一首',
        action: () => {
          const trackAndPrivilege = new TrackAndPrivilege()
          trackAndPrivilege.track = track as ESObject as Track
          trackAndPrivilege.privilege = track.privilege as ESObject as Privilege
          globalPlaylist.insertOrMoveNext(trackAndPrivilege)
        }
      },
      {
        value: '收藏到歌单',
        action: () => {
          this.nowSelected = track.id
          this.showPlayListSelector = true;
        }
      },
    ])
  }

  aboutToAppear() {
    this.searchResults = []
    this.showResults = false
    this.offsetValue = 0
    this.hasMore = true

    const params = router.getParams()
    if (params) {
      const keyword = Object(params).keywords as string
      this.ignoreNextSuggestions = true
      this.searchText = keyword
      this.handleSearch()
    }
  }

  async handleSearch(loadMore: boolean = false) {
    if (!this.searchText.trim()) {
      this.searchResults = []
      this.playlistResults = []
      this.showResults = false
      return
    }

    if (loadMore) {
      if (this.isLoadingMore || !this.hasMore) {
        return
      }
      this.isLoadingMore = true
    } else {
      this.isLoading = true
      this.showResults = false
      this.offsetValue = 0
      this.hasMore = true
    }

    try {
      const result = await search({
        keywords: this.searchText,
        limit: this.pageSize,
        offset: this.offsetValue * this.pageSize,
        type: this.tabs[this.currentTab].type
      })

      if (this.tabs[this.currentTab].type === SearchType.SINGLE) {
        if (result?.result?.songs) {
          const newSongs = result.result.songs
          this.hasMore = newSongs.length === this.pageSize
          animateTo({
            duration: 300,
            curve: Curve.EaseOut
          }, () => {
            if (loadMore) {
              this.searchResults = [...this.searchResults, ...newSongs]
            } else {
              this.searchResults = newSongs
            }
            this.showResults = true
          })
        }
      } else if (this.tabs[this.currentTab].type === SearchType.PLAYLIST) {
        if (result?.result?.playlists) {
          const newPlaylists = result.result.playlists
          this.hasMore = newPlaylists.length === this.pageSize
          animateTo({
            duration: 300,
            curve: Curve.EaseOut
          }, () => {
            if (loadMore) {
              this.playlistResults = [...this.playlistResults, ...newPlaylists]
            } else {
              this.playlistResults = newPlaylists
            }
            this.showResults = true
          })
        }
      }

      this.offsetValue += 1
    } catch (error) {
      if (!loadMore) {
        this.searchResults = []
        this.playlistResults = []
      }
      this.showResults = true
      this.hasMore = false
    } finally {
      if (loadMore) {
        this.isLoadingMore = false
      } else {
        this.isLoading = false
      }
    }
  }

  @Builder
  SearchHeader() {
    Column() {
      // 搜索框
      Row() {
        Search({
          value: this.searchText,
          placeholder: '搜索音乐、歌手、专辑、歌单',
          controller: this.searchController
        })
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.search_background'))
          .expandSafeArea()
          .placeholderColor($r('app.color.search_placeholder'))
          .fontColor($r('app.color.search_text'))
          .placeholderFont({ size: 16 })
          .textFont({ size: 16 })
          .borderRadius(20)
          .onChange((value: string) => {
            this.searchText = value
            this.debounce(() => {
              this.fetchSuggestions(value)
            })
          })
          .onSubmit(() => {
            this.suggestions = []
            this.handleSearch()
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 8,
        bottom: 8
      })

      // 搜索建议标签
      if (this.suggestions.length > 0) {
        Flex({
          direction: FlexDirection.Row,
          wrap: FlexWrap.Wrap
        }) {
          ForEach(this.suggestions, (item: SearchSuggest) => {
            Text(item.keyword)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.search_background'))
              .padding({
                left: 12,
                right: 12,
                top: 6,
                bottom: 6
              })
              .borderRadius(16)
              .margin({ right: 8, bottom: 8 })
              .opacity(this.animationState)
              .animation({
                duration: 200,
                curve: Curve.EaseOut
              })
              .onClick(() => {
                this.ignoreNextSuggestions = true
                this.searchText = item.keyword
                this.suggestions = []
                this.handleSearch()
              })
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .opacity(this.animationState)
        .animation({
          duration: 200,
          curve: Curve.EaseOut
        })
      }

      // 分类标签
      Row() {
        Row() {
          ForEach(this.tabs, (tab: TabItem, index: number) => {
            Text(tab.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .height(32)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.currentTab === index ? $r('app.color.primary_blue') : Color.Transparent)
              .borderRadius(16)
              .fontColor(this.currentTab === index ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .margin({ right: index === this.tabs.length - 1 ? 0 : 8 })
              .onClick(() => {
                if (this.currentTab !== index) {
                  animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                    this.currentTab = index
                    this.handleSearch()
                  })
                }
              })
          })
        }
        .padding(4)
        .borderRadius(20)
        .backgroundColor($r('app.color.button_ghost_background'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .expandSafeArea()
  }

  @Builder
  PlaylistResults() {
    if (!this.isLoading && this.showResults && this.playlistResults?.length > 0) {
      List({ space: 4 }) {
        ListItem() {
          Text('歌单')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, top: 8, bottom: 8 })
        }

        ForEach(this.playlistResults, (playlist: Playlist, index: number) => {
          ListItem() {
            PlaylistCard({
              count: playlist.trackCount,
              coverUrl: playlist.coverImgUrl,
              title: playlist.name,
              creator: playlist.creator.nickname,
              index: index
            })
              .onClick(() => {
                AppStorage.setOrCreate("CollectionId", playlist.id);
                router.pushUrl({
                  url: "pages/Collection",
                });
              })
          }
        })

        ListItem() {
          this.LoadMoreIndicator()
        }
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .onReachEnd(() => {
        if (this.hasMore && !this.isLoadingMore) {
          this.handleSearch(true)
        }
      })
      .expandSafeArea()
    }
  }

  @Builder
  LoadingState() {
    if (this.isLoading) {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.primary_blue'))
        Text('搜索中...')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  LoadMoreIndicator() {
    if (this.isLoadingMore) {
      Row() {
        LoadingProgress()
          .width(24)
          .height(24)
          .color($r('app.color.text_secondary'))
        Text('加载更多...')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center)
    } else if (!this.hasMore && (this.searchResults.length > 0 || this.playlistResults.length > 0)) {
      Row() {
        Text('没有更多了')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  EmptyState() {
    if (!this.searchText) {
      Column() {
        Text('搜索你想听的')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.showResults && (!this.searchResults || this.searchResults.length === 0) &&
      (!this.playlistResults || this.playlistResults.length === 0)) {
      Column() {
        Image($r('app.media.ic_brush'))
          .width(120)
          .height(120)
          .fillColor($r('app.color.icon_color'))
          .opacity(0.5)
        Text('暂无搜索结果')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  SearchResults() {
    if (!this.isLoading && this.showResults && this.searchResults?.length > 0) {
      List({ space: 4 }) {
        ListItem() {
          Text('搜索结果')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, top: 8, bottom: 8 })
        }

        ForEach(this.searchResults, (song: SongDetail, index: number) => {
          ListItem() {
            SongListCard({
              title: song.name,
              artist: song.ar as ESObject as Artist[],
              coverUrl: cover(song.al.picUrl, 100),
              index,
              coverSize: 56,
              tns: song.tns,
              disabled: !isTrackPlayableWithParams(song as ESObject as Track, song.privilege as ESObject as Privilege)
                .isPlayable,
              active: (!!this.track && this.track.track.id == song.id) ?? false,
              rightSlot: () => {
                this.MoreActions(song)
              }
            })
              .onClick(() => {
                if (this.searchResults && this.searchResults.length > 0) {
                  const info = new TrackAndPrivilege()
                  info.track = song as ESObject as Track
                  info.privilege = song.privilege as ESObject as Privilege
                  const playableResult = isTrackPlayableWithParams(info.track, info.privilege)
                  if (!playableResult.isPlayable) {
                    promptAction.showToast({ message: playableResult.reason })
                    return
                  }
                  globalPlaylist.insertTop(info)
                  AppStorage.setOrCreate("Track", info);
                  router.pushUrl({
                    url: 'pages/Playing'
                  }, router.RouterMode.Single)
                }
              })
          }.expandSafeArea()
        })

        ListItem() {
          this.LoadMoreIndicator()
        }
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .onReachEnd(() => {
        if (this.hasMore && !this.isLoadingMore) {
          this.handleSearch(true)
        }
      })
      .expandSafeArea()
    }
  }

  build() {
    Stack() {
      Column() {
        this.SearchHeader()

        Stack() {
          this.EmptyState()
          this.LoadingState()
          if (this.currentTab === 0) {
            this.SearchResults()
          } else {
            this.PlaylistResults()
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.search_background'))
      .expandSafeArea()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea()
    .bindSheet($$this.showPlayListSelector, this.PlayList(), {
      showClose: false,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      backgroundColor: $r('app.color.playlist_bg'),
      preferType: SheetType.BOTTOM,
    })
  }
}
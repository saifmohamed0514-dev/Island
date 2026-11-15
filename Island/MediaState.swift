import Foundation

// Adapter diffs distinguish a missing field from a field explicitly cleared to null.
struct NowPlayingUpdate:Decodable {
    let payload:NowPlayingPayload
    let diff:Bool?
}
struct NowPlayingPayload:Decodable {
    enum Key:String,CodingKey,CaseIterable {
        case title,artist,album,duration,elapsedTime,shuffleMode,repeatMode,artworkData,timestamp,playbackRate,playing,parentApplicationBundleIdentifier,bundleIdentifier,volume,isLiked,supportsIsLiked,mediaType,prohibitsSkip,supportsFastForward15Seconds,supportsRewind15Seconds
    }
    let keys:Set<Key>
    let title,artist,album,artworkData,timestamp,parentApplicationBundleIdentifier,bundleIdentifier:String?
    let duration,elapsedTime,playbackRate,volume:Double?
    let shuffleMode,repeatMode,mediaType:Int?
    let playing,isLiked,supportsIsLiked,prohibitsSkip,supportsFastForward15Seconds,supportsRewind15Seconds:Bool?
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:Key.self);keys=Set(c.allKeys)
        title=try c.decodeIfPresent(String.self,forKey:.title);artist=try c.decodeIfPresent(String.self,forKey:.artist);album=try c.decodeIfPresent(String.self,forKey:.album)
        artworkData=try c.decodeIfPresent(String.self,forKey:.artworkData);timestamp=try c.decodeIfPresent(String.self,forKey:.timestamp)
        parentApplicationBundleIdentifier=try c.decodeIfPresent(String.self,forKey:.parentApplicationBundleIdentifier);bundleIdentifier=try c.decodeIfPresent(String.self,forKey:.bundleIdentifier)
        duration=try c.decodeIfPresent(Double.self,forKey:.duration);elapsedTime=try c.decodeIfPresent(Double.self,forKey:.elapsedTime);playbackRate=try c.decodeIfPresent(Double.self,forKey:.playbackRate);volume=try c.decodeIfPresent(Double.self,forKey:.volume)
        shuffleMode=try c.decodeIfPresent(Int.self,forKey:.shuffleMode);repeatMode=try c.decodeIfPresent(Int.self,forKey:.repeatMode);mediaType=try? c.decodeIfPresent(Int.self,forKey:.mediaType)
        playing=try c.decodeIfPresent(Bool.self,forKey:.playing);isLiked=try c.decodeIfPresent(Bool.self,forKey:.isLiked);supportsIsLiked=try c.decodeIfPresent(Bool.self,forKey:.supportsIsLiked);prohibitsSkip=try c.decodeIfPresent(Bool.self,forKey:.prohibitsSkip)
        supportsFastForward15Seconds=try c.decodeIfPresent(Bool.self,forKey:.supportsFastForward15Seconds);supportsRewind15Seconds=try c.decodeIfPresent(Bool.self,forKey:.supportsRewind15Seconds)
    }
}
enum IslandMediaRules {
    static func finite(_ value:Double,default fallback:Double=0)->Double { value.isFinite ? value : fallback }
    static func position(_ state:PlaybackState,at now:Date)->Double {
        let age=max(0,min(86400,now.timeIntervalSince(state.lastUpdated)))
        let elapsed=max(0,finite(state.currentTime)+(state.isPlaying ? age*max(0,finite(state.playbackRate,default:1)) : 0))
        return state.duration>0 ? min(elapsed,state.duration) : elapsed
    }
    static func reduce(_ update:NowPlayingUpdate,previous:PlaybackState,now:Date)->PlaybackState {
        let p=update.payload
        let source=p.parentApplicationBundleIdentifier ?? p.bundleIdentifier ?? (p.keys.contains(.bundleIdentifier) ? "" : nil)
        let sameSource=source == nil || source == previous.bundleIdentifier
        let incremental=update.diff == true && sameSource
        var state=incremental ? previous : PlaybackState(bundleIdentifier:source ?? "",title:"")
        if incremental { state.currentTime=position(previous,at:now) }
        if let source { state.bundleIdentifier=source }
        if p.keys.contains(.title) { state.title=p.title ?? "" }
        if p.keys.contains(.artist) { state.artist=p.artist ?? "" }
        if p.keys.contains(.album) { state.album=p.album ?? "" }
        let changedTrack=state.title != previous.title || state.artist != previous.artist || !sameSource
        let confirmedSameAlbum=sameSource && p.keys.contains(.album) && !state.album.isEmpty && state.album==previous.album && state.artist==previous.artist
        if changedTrack {
            if !confirmedSameAlbum { state.artwork=nil }
            state.isFavorite=false
            if !p.keys.contains(.duration) { state.duration=0 }
        }
        if state.album != previous.album { state.artwork=nil }
        if p.keys.contains(.duration) { state.duration=max(0,finite(p.duration ?? 0)) }
        if p.keys.contains(.elapsedTime) { state.currentTime=max(0,finite(p.elapsedTime ?? 0)) }
        else if changedTrack { state.currentTime=0 }
        if p.keys.contains(.playbackRate) { state.playbackRate=min(16,max(0,finite(p.playbackRate ?? 1,default:1))) }
        if p.keys.contains(.playing) { state.isPlaying=p.playing ?? false }
        if p.keys.contains(.volume) { state.volume=min(1,max(0,finite(p.volume ?? 0.5,default:0.5))) }
        if p.keys.contains(.shuffleMode) { state.isShuffled=(p.shuffleMode ?? 1) != 1;state.shuffleAvailable=p.shuffleMode != nil }
        if p.keys.contains(.repeatMode) { state.repeatMode=RepeatMode(rawValue:p.repeatMode ?? 1) ?? .off;state.repeatAvailable=p.repeatMode != nil }
        if p.keys.contains(.artworkData) { state.artwork=p.artworkData.flatMap { Data(base64Encoded:$0.trimmingCharacters(in:.whitespacesAndNewlines)) } }
        if p.keys.contains(.isLiked) { state.isFavorite=p.isLiked ?? false }
        if p.keys.contains(.supportsFastForward15Seconds) { state.supportsForward15=p.supportsFastForward15Seconds ?? false }
        if p.keys.contains(.supportsRewind15Seconds) { state.supportsBackward15=p.supportsRewind15Seconds ?? false }
        if p.keys.contains(.prohibitsSkip) { state.prohibitsSkip=p.prohibitsSkip ?? false }
        // Rebase on every update so pause/resume and rate changes cannot count time twice.
        state.lastUpdated=now
        if let raw=p.timestamp,let stamp=parseDate(raw),p.elapsedTime != nil {
            let age=max(0,min(30,now.timeIntervalSince(stamp)))
            if state.isPlaying { state.currentTime+=age*state.playbackRate }
        }
        state.currentTime=max(0,finite(state.currentTime))
        if state.duration>0 { state.currentTime=min(state.currentTime,state.duration) }
        return state
    }
    static func parseDate(_ raw:String)->Date? {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return f.date(from:raw) ?? ISO8601DateFormatter().date(from:raw)
    }
    static func time(_ seconds:Double)->String {
        guard seconds.isFinite else { return "0:00" }
        let s=Int(min(359999,max(0,seconds)));return s>=3600 ? String(format:"%d:%02d:%02d",s/3600,(s/60)%60,s%60) : String(format:"%d:%02d",s/60,s%60)
    }
    static func skip(position:Double,seconds:Double,duration:Double)->Double {
        let next=max(0,finite(position)+finite(seconds));return duration>0 ? min(next,duration) : next
    }
}

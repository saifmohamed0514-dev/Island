import Foundation
import AppKit

struct IslandPlayerCapabilities:Equatable {
    var favoriteProperty:String?
    var explicitProperty:String?
    var speedProperty:String?
    static func parse(_ data:Data)->Self {
        guard data.count<=2097152 else { return .init() }
        let parser=XMLParser(data:data),reader=Reader();parser.delegate=reader;parser.shouldResolveExternalEntities=false
        return parser.parse() ? reader.value : .init()
    }
    static func spotify()->Self {
        guard let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.spotify.client"),let urls=try? FileManager.default.contentsOfDirectory(at:app.appendingPathComponent("Contents/Resources"),includingPropertiesForKeys:nil),let url=urls.first(where:{ $0.pathExtension=="sdef" }),let data=try? Data(contentsOf:url) else { return .init() };return parse(data)
    }
    private final class Reader:NSObject,XMLParserDelegate {
        var value=IslandPlayerCapabilities(),owner=""
        func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]) {
            if elementName=="class" || elementName=="class-extension" { owner=a["name"] ?? a["extends"] ?? "" }
            guard elementName=="property",let name=a["name"],let type=a["type"] else { return }
            if owner=="track",type=="boolean" {
                if ["liked","favorited","loved","starred"].contains(name),a["access"] != "r",value.favoriteProperty==nil { value.favoriteProperty=name }
                if ["explicit","explicit content"].contains(name) { value.explicitProperty=name }
            }
            if owner=="application",["real","number","double"].contains(type),["playback speed","playback rate"].contains(name),a["access"] != "r" { value.speedProperty=name }
        }
        func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?) { if elementName=="class" || elementName=="class-extension" { owner="" } }
    }
}
enum IslandTrackLink {
    static func safe(_ raw:String?)->URL? {
        guard let raw,raw.utf8.count<4096 else { return nil }
        if raw.hasPrefix("spotify:") {
            let parts=raw.split(separator:":");guard parts.count==3,["track","episode","playlist"].contains(parts[1]),parts[2].range(of:#"^[A-Za-z0-9]+$"#,options:.regularExpression) != nil else { return nil }
            return URL(string:"https://open.spotify.com/\(parts[1])/\(parts[2])")
        }
        guard let url=URL(string:raw),url.scheme=="https",url.user==nil,url.password==nil,let host=url.host?.lowercased(),["open.spotify.com","music.apple.com","youtube.com","www.youtube.com","music.youtube.com","youtu.be"].contains(host) else { return nil };return url
    }
}

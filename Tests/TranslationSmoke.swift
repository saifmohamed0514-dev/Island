import Foundation
@main struct TranslationSmoke {
 static func main() throws {
    func parse(_ status:String,_ output:[[String:Any]]) throws -> String? {
        let data = try JSONSerialization.data(withJSONObject:["status":status,"output":output])
        return try JSONDecoder().decode(IslandTranslationResponse.self,from:data).translation
    }
    let text:[[String:Any]] = [["type":"message","content":[["type":"output_text","text":"Bonjour"]]]]
    precondition(try! parse("completed",text) == "Bonjour")
    precondition(try! parse("incomplete",text) == nil)
    precondition(try! parse("failed",text) == nil)
    precondition(try! parse("completed",[]) == nil)
    precondition(try! parse("completed",[["type":"reasoning","content":[["type":"output_text","text":"hidden"]]]]) == nil)
    precondition(try! parse("completed",text+[["type":"message","content":[["type":"refusal"]]]]) == nil)
    print("PASS: 6 translation response decoding checks (fixtures, no cloud request)")
 }
}

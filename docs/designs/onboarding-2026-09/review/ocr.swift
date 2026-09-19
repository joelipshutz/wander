import Foundation
import Vision
import AppKit
let paths=CommandLine.arguments.dropFirst()
for path in paths {
 let url=URL(fileURLWithPath:path)
 let req=VNRecognizeTextRequest()
 req.recognitionLevel = .accurate
 req.usesLanguageCorrection = false
 do {
  try VNImageRequestHandler(url:url).perform([req])
  let texts=(req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
  let obj:[String:Any] = ["file":url.lastPathComponent,"text":texts]
  let data=try JSONSerialization.data(withJSONObject:obj,options:[.sortedKeys])
  print(String(data:data,encoding:.utf8)!)
 } catch {print("{}")}
}

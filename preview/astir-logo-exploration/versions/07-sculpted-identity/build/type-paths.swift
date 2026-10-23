import AppKit
import CoreText
var result: [String:Any] = [:]
for (key,tracking) in [("current",CGFloat(26)),("narrow",CGFloat(-24)),("refined",CGFloat(0))] {
 let font: NSFont
 if key == "refined" { font = NSFont(name:"BodoniSvtyTwoITCTT-Book",size:1000)! }
 else { let descriptor=NSFont.systemFont(ofSize:1000,weight:.medium).fontDescriptor.withDesign(.serif)!;font=NSFont(descriptor:descriptor,size:1000)! }
 let ct=font as CTFont;let chars=Array("STIR".utf16);var glyphs=[CGGlyph](repeating:0,count:4)
 CTFontGetGlyphsForCharacters(ct,chars,&glyphs,4)
 var advances=[CGSize](repeating:.zero,count:4);CTFontGetAdvancesForGlyphs(ct,.horizontal,glyphs,&advances,4)
 var x:CGFloat=0;var paths:[String]=[];var bounds=CGRect.null
 for i in 0..<4 {
  if let path=CTFontCreatePathForGlyph(ct,glyphs[i],nil) {
   bounds=bounds.union(path.boundingBoxOfPath.offsetBy(dx:x,dy:0));var d=""
   path.applyWithBlock { ptr in let e=ptr.pointee
    func pt(_ n:Int)->String {String(format:"%.4f %.4f",Double(e.points[n].x+x),Double(-e.points[n].y))}
    switch e.type {case .moveToPoint:d+="M"+pt(0);case .addLineToPoint:d+="L"+pt(0);case .addQuadCurveToPoint:d+="Q"+pt(0)+" "+pt(1);case .addCurveToPoint:d+="C"+pt(0)+" "+pt(1)+" "+pt(2);case .closeSubpath:d+="Z";@unknown default:break}
   };paths.append(d)
  };x += advances[i].width+tracking
 }
 result[key] = ["font":font.fontName,"tracking":tracking,"capHeight":CTFontGetCapHeight(ct),"bounds":[bounds.minX,-bounds.maxY,bounds.width,bounds.height],"advance":x-tracking,"paths":paths]
}
print(String(data:try! JSONSerialization.data(withJSONObject:result,options:.prettyPrinted),encoding:.utf8)!)

import SwiftUI
import UIKit
import Combine
import Contacts
import AVFoundation
import EventKit
import Photos
struct AppBrand { static let displayName = "Astir" }
enum NativeAuthMode { case signIn,signUp,signInOrUp }
enum NativeSocialAuthProvider { case apple,google }
enum NativeAuthOutcome { case completed }
class AuthSessionStore: ObservableObject {
 @Published var emailVerificationAddress: String? = nil
 var isPerformingNativeAuth=false,isSendingEmailCode=false,isVerifyingEmailCode=false,isSigningInWithPassword=false
 var activeSocialAuthProvider:NativeSocialAuthProvider?=nil
 var nativeAuthError:String?=nil
 func cancelEmailVerification(){emailVerificationAddress=nil}
 func authenticate(with:NativeSocialAuthProvider)async{}
 func sendEmailCode(to address:String)async{emailVerificationAddress=address}
 func verifyEmailCode(_ code:String)async{}
 func signInWithPassword(emailAddress:String,password:String)async->NativeAuthOutcome?{nil}
}
enum OnboardingStep: CaseIterable {case identity,location,contacts,friends,notifications}
class WanderBackend:ObservableObject{}
struct AuthSession{var userID="demo";var displayName:String?="Alex";var handle:String?="alex_places"}
struct AnalyticsClient{}
struct ProfileIdentityDraft {
 var displayName:String;var handle:String
 var normalizedHandle:String{handle};var isValid:Bool{true};var validationError:Validation?{nil}
 struct Validation{var message:String}
}
enum WanderImageProcessingError:Error{case invalidImageData}
struct WanderImageProcessor{static func squareJPEGData(from image:UIImage,cropRect:CGRect)throws->Data{image.jpegData(compressionQuality:0.9)!}}
struct WanderPrimaryButton:View {
 let title:String;var systemImage:String?;var isDisabled=false;let action:()->Void
 var body:some View{Button(action:action){HStack{if let systemImage{Image(systemName:systemImage)};Text(title)}.font(AstirTypography.control).frame(maxWidth:.infinity,minHeight:52).background(isDisabled ? WanderTheme.borderStrong.color:WanderTheme.terracotta.color).foregroundStyle(AstirTheme.ink.color).clipShape(RoundedRectangle(cornerRadius:WanderTheme.radiusLarge,style:.continuous))}.buttonStyle(.plain).disabled(isDisabled)}
}
struct ProductUpsellContent {
 enum Palette {case sun}
 let palette=Palette.sun;let systemImage="bell.badge.fill";let eyebrow="STAY IN THE LOOP";let title="See when your friends check in";let message="Get a heads-up when people you follow save a place or check in somewhere worth knowing."
}
@main struct PreviewApp:App {
 @StateObject var auth=AuthSessionStore();@StateObject var backend=WanderBackend()
 let route=ProcessInfo.processInfo.arguments.last ?? "signup"
 var body:some Scene{WindowGroup{content.environmentObject(auth).environmentObject(backend).environment(\.astirBrandMode,.editorialLight).preferredColorScheme(.light)}}
 @ViewBuilder var content:some View {
  switch route {
  case "signup":NativeAuthFlowView(isDismissable:true,mode:.signUp)
  case "verify":NativeAuthFlowView(isDismissable:true,mode:.signUp).onAppear{auth.emailVerificationAddress="review@example.com"}
  case "crop":ProfilePhotoCropView(image:UIImage(contentsOfFile:Bundle.main.path(forResource:"fixture-photo",ofType:"jpg")!)!,cancel:{},choose:{_,_ in})
  case "recovery":AppEntryRecoveryView(title:"Your map is still here",message:"",canContinueOffline:true,retry:{},continueOffline:{})
  case "friends-empty","friends-loaded":OnboardingStepScaffold(step:.friends){VStack(alignment:.leading,spacing:WanderTheme.spacing4){OnboardingHeadline(eyebrow:"YOUR TRUSTED MAP",title:"Astir is better with people",message:"Start with a few people whose taste you’d like to see. You’re always in control of who you follow.").padding(.horizontal,WanderTheme.spacing4);if route == "friends-loaded" {ScrollView {VStack(spacing:WanderTheme.spacing2) {ForEach(0..<3) { i in OnboardingFriendRow(recommendation:DiscoverPeopleRecommendation(profile:.init(displayName:["Sam Rivera","Jordan Lee","Casey Morgan"][i],handle:["sam_places","jordan_explores","casey_outdoors"][i]),reason:i == 1 ? .sharedFollows(3) : .suggested),isSelected:i != 1)}}.padding(.horizontal,WanderTheme.spacing4)}} else {OnboardingEmptySuggestions(title:"Your people will show up here",message:"Skip for now — we’ll keep finding trusted people as Astir grows.")}}.padding(.top,WanderTheme.spacing2)}footer:{VStack(spacing:WanderTheme.spacing1){WanderPrimaryButton(title:route == "friends-loaded" ? "Follow 2 people" : "Continue"){};Button("Skip"){}.font(AstirTypography.control).foregroundStyle(WanderTheme.textMuted.color).frame(maxWidth:.infinity,minHeight:WanderTheme.tapMinimum)}}
  case "notifications-denied":OnboardingStepScaffold(step:.notifications){ProductUpsellContentView(content:ProductUpsellContent(),isWorking:false)}footer:{VStack(spacing:WanderTheme.spacing1){WanderPrimaryButton(title:"Open Settings"){};Button("Not now"){}.font(AstirTypography.control).foregroundStyle(AstirTheme.mutedOnPaper.color).frame(maxWidth:.infinity,minHeight:WanderTheme.tapMinimum)}}
  case "identity-checking","identity-available","identity-taken","identity-saving":OnboardingIdentityView(session:AuthSession(),analytics:AnalyticsClient(),continueAction:{})
  default:Color(hexFixture:"F2E9DB").ignoresSafeArea().task{try? await Task.sleep(for:.seconds(1));await permission()}
  }
 }
 func permission()async {
  switch route {
  case "system-contacts":_ = try? await CNContactStore().requestAccess(for:.contacts)
  case "system-camera":_ = await AVCaptureDevice.requestAccess(for:.video)
  case "system-calendar":_ = try? await EKEventStore().requestFullAccessToEvents()
  case "system-photos":_ = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
  default:break
  }
 }
}
extension Color {init(hexFixture:String){self.init(red:242/255,green:233/255,blue:219/255)}}

struct DiscoverPeopleRecommendation {
 struct Profile {var displayName:String;var handle:String;var avatarURL:URL?=nil}
 enum Reason {case followsYou,sharedFollows(Int),suggested}
 var profile:Profile;var reason:Reason
}
struct WanderAvatar:View {
 var initials:String;var avatarURL:URL?;var size:CGFloat;var color:Color
 var body:some View {Text(initials).font(.system(size:max(12,size*0.34),weight:.black)).foregroundStyle(WanderTheme.textOnAction.color).frame(width:size,height:size).background(color).clipShape(Circle()).overlay(Circle().stroke(WanderTheme.surfaceRaised.color,lineWidth:2))}
}

#if DEBUG && targetEnvironment(simulator)
import Foundation

enum PersonTypeaheadUITestFixtures {
    static let profiles: [ProfileShell] = [
        ("fixture_caitlin", "cait123", "Caitlin Cortez"),
        ("fixture_camilo", "camilo", "Camilo Flores"),
        ("fixture_abdou", "abdou", "Abdou Diallo"),
        ("fixture_joey", "joey", "Joey Williams"),
        ("fixture_molly", "molly", "Molly Pellkoffer"),
        ("fixture_dylan", "dylan", "Dylan Kruger"),
        ("fixture_eva", "eva", "Eva Morales"),
        ("fixture_long", "alexandra", "Alexandra Montgomery Rivera")
    ].map { id, handle, name in
        ProfileShell(id: id, handle: handle, displayName: name, avatarURL: nil, bio: nil, relationship: .mutual)
    }
}
#endif

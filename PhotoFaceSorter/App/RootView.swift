import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            PeopleView()
                .tabItem { Label("人物", systemImage: "person.2") }
            ClassificationReviewView()
                .tabItem { Label("归类", systemImage: "checklist") }
            ScanView()
                .tabItem { Label("扫描", systemImage: "viewfinder") }
            RulesView()
                .tabItem { Label("规则", systemImage: "wand.and.stars") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

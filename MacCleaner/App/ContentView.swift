import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CleanTabView()
                .tabItem {
                    Label("Clean", systemImage: "sparkles")
                }
            SystemTabView()
                .tabItem {
                    Label("System", systemImage: "cpu")
                }
        }
        .frame(minWidth: 980, minHeight: 660)
    }
}

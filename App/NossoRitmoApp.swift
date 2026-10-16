import SwiftUI
import CloudKit
@preconcurrency import UserNotifications

@MainActor final class InviteInbox: ObservableObject {
    static let shared = InviteInbox()
    @Published var metadata: CKShare.Metadata?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self; return true
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in InviteInbox.shared.metadata = metadata }
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = RhythmSceneDelegate.self; return configuration
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let value = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: value) {
            await MainActor.run { NotificationCenter.default.post(name: .rhythmURL, object: url) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
final class RhythmSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata { Task { @MainActor in InviteInbox.shared.metadata = metadata } }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in InviteInbox.shared.metadata = metadata }
    }
}

@main struct NossoRitmoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("storageMode") private var mode = ""
    @AppStorage("theme") private var theme = "system"
    var body: some Scene {
        WindowGroup {
            Group {
                if mode.isEmpty { WelcomeView() }
                else { ModeView(demo: mode == "demo").id(mode) }
            }
            .tint(theme == "pink" ? Color(red: 0.77, green: 0.23, blue: 0.42) : Color(red: 0.31, green: 0.42, blue: 0.36))
            .preferredColorScheme(theme == "dark" ? .dark : (theme == "light" || theme == "pink" ? .light : nil))
            .environment(\.locale, Locale(identifier: "pt_BR"))
        }
    }
}

struct WelcomeView: View {
    @AppStorage("storageMode") var mode = ""
    @ObservedObject var inbox = InviteInbox.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "heart.circle.fill").font(.system(size: 72)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Nosso\nRitmo").font(.system(.largeTitle, design: .serif, weight: .medium))
                    Text("Mais espaço para a vida que vocês constroem juntos.").font(.title3).foregroundStyle(.secondary)
                    Text("Agenda, metas e pequenos momentos. Um lugar só de vocês, em cada iPhone.")
                    Button("Começar com iCloud", systemImage: "icloud") { mode = "cloud" }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Explorar demonstração", systemImage: "sparkles") { mode = "demo" }.buttonStyle(.bordered)
                    Text("A demonstração usa dados fictícios e não sincroniza. O modo iCloud exige configuração Apple Developer no projeto.").font(.footnote).foregroundStyle(.secondary)
                }.padding(32)
            }.navigationTitle("")
        }
    }
}

struct ModeView: View {
    @StateObject var store: RhythmStore
    @ObservedObject var inbox = InviteInbox.shared
    @Environment(\.scenePhase) var phase
    init(demo: Bool) { _store = StateObject(wrappedValue: RhythmStore(demo: demo)) }
    var body: some View {
        LoadedView(persistence: store.persistence)
            .environmentObject(store)
            .alert("Vamos ajustar isso", isPresented: Binding(get: { store.error != nil || store.persistence.error != nil }, set: { if !$0 { store.error = nil; store.persistence.error = nil } })) {
                Button("Entendi", role: .cancel) { store.error = nil; store.persistence.error = nil }
            } message: { Text(store.error ?? store.persistence.error ?? "") }
            .sheet(isPresented: $store.showingShare) {
                InvitationView()
            }
            .onOpenURL { store.route($0) }
            .onReceive(NotificationCenter.default.publisher(for: .rhythmURL)) { if let url = $0.object as? URL { store.route(url) } }
            .onChange(of: phase) { _, value in if value == .active { store.reload(); Task { await store.identify(); await acceptPending() } } }
            .onChange(of: inbox.metadata?.share.recordID.recordName) { _, _ in Task { await acceptPending() } }
            .onChange(of: store.persistence.loaded) { _, ready in if ready { Task { await acceptPending() } } }
    }
    func acceptPending() async {
        guard store.persistence.loaded, let metadata = inbox.metadata else { return }
        await store.accept(metadata); inbox.metadata = nil
    }
}

struct LoadedView: View {
    @ObservedObject var persistence: Persistence
    @EnvironmentObject var store: RhythmStore
    @State var name = ""
    @AppStorage("storageMode") var mode = ""
    var body: some View {
        Group {
            if !persistence.loaded {
                VStack(spacing: 20) {
                    ProgressView(persistence.status)
                    Button("Voltar ao início") { mode = "" }
                }.padding()
            } else if store.root == nil || store.myID == nil {
                NavigationStack {
                    Form {
                        Section {
                            Text("Um espaço para nós").font(.title2).fontDesign(.serif)
                            Text("Cada pessoa usa sua própria conta iCloud. Uma cria o espaço e convida a outra.")
                            TextField("Seu nome", text: $name).textContentType(.givenName)
                        }
                        if store.root == nil {
                            if store.waitingForSharedSpace { ProgressView("Recebendo o espaço compartilhado…") }
                            Button("Criar nosso espaço") { store.createSpace(name: name) }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || store.waitingForSharedSpace)
                            Section("Recebeu um convite?") { Text("Abra o link enviado pela outra pessoa. Não crie um segundo espaço se você vai entrar no espaço dela.") }
                        } else { Button("Entrar como \(name)") { store.registerMember(name) }.disabled(name.isEmpty || store.members.count >= 2) }
                        Button("Verificar iCloud novamente") { Task { await store.identify(); store.reload() } }
                        Button("Voltar ao início") { mode = "" }
                    }.navigationTitle("Bem-vindos")
                }
            } else { MainTabs() }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var store: RhythmStore
    @AppStorage("theme") var theme = "system"
    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { TodayView() }.tabItem { Label("Hoje", systemImage: "sun.horizon") }.tag(0)
            NavigationStack { AgendaView() }.tabItem { Label("Agenda", systemImage: "calendar") }.tag(1)
            NavigationStack { GoalsView() }.tabItem { Label("Metas", systemImage: "scope") }.tag(2)
            NavigationStack { TripsView() }.tabItem { Label("Viagens", systemImage: "suitcase.rolling") }.tag(3)
            NavigationStack { TogetherView() }.tabItem { Label("Nós", systemImage: "heart") }.tag(4)
        }
        .rhythmSurface()
    }
}

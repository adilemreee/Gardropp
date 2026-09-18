import SwiftData
import SwiftUI

@main
struct GardroppApp: App {
    @State private var appSettings = AppSettings()
    @State private var aiSettings: AISettings
    @State private var aiService: AIService
    @State private var weather = WeatherService()

    private let container: ModelContainer

    init() {
        let aiSettings = AISettings()
        _aiSettings = State(initialValue: aiSettings)
        _aiService = State(initialValue: AIService(settings: aiSettings))

        do {
            container = try ModelContainer(
                for: ClothingItem.self, Outfit.self, StorageLocation.self, WearEvent.self
            )
        } catch {
            // A corrupt store should not brick the app; start from a clean one.
            container = try! ModelContainer(
                for: ClothingItem.self, Outfit.self, StorageLocation.self, WearEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environment(appSettings)
                .environment(aiSettings)
                .environment(aiService)
                .environment(weather)
                .tint(Color.textPrimary)
        }
        .modelContainer(container)
    }
}

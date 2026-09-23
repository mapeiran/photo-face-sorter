import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if model.people.isEmpty {
                    ContentUnavailableView("暂无人物",
                                           systemImage: "person.2",
                                           description: Text("先到「扫描」识别人像"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(model.people) { person in
                                NavigationLink {
                                    PersonDetailView(person: person)
                                } label: {
                                    personCell(person)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("人物")
        }
    }

    private func personCell(_ person: Person) -> some View {
        let sample = model.samples(of: person).first
        return VStack(spacing: 6) {
            ZStack {
                if let sample {
                    AssetThumbnailView(localIdentifier: sample.assetLocalIdentifier,
                                       boundingBox: sample.boundingBox,
                                       side: 80)
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            Text(person.displayName).font(.caption).lineLimit(1)
            Text("\(model.samples(of: person).count) 张")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

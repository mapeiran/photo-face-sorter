import SwiftUI

struct PersonDetailView: View {
    @EnvironmentObject var model: AppModel
    @State var person: Person

    @State private var newName = ""
    @State private var showRename = false

    var body: some View {
        List {
            Section("名称") {
                HStack {
                    Text(person.displayName)
                    Spacer()
                    Button("重命名") {
                        newName = person.name
                        showRename = true
                    }
                }
            }

            Section("照片（\(model.samples(of: person).count)）") {
                if model.samples(of: person).isEmpty {
                    Text("暂无样本人脸").foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                        ForEach(model.samples(of: person)) { sample in
                            AssetThumbnailView(localIdentifier: sample.assetLocalIdentifier,
                                               boundingBox: sample.boundingBox,
                                               side: 80)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .navigationTitle(person.displayName)
        .alert("重命名", isPresented: $showRename) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                model.renamePerson(person, to: newName)
                person.name = newName
            }
        }
    }
}

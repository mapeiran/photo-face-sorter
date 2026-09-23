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

            Section("人脸样本（\(model.samples(of: person).count)）") {
                if model.samples(of: person).isEmpty {
                    Text("暂无样本人脸").foregroundColor(.secondary)
                } else {
                    ForEach(model.samples(of: person)) { sample in
                        Text(sample.assetLocalIdentifier)
                            .font(.caption)
                            .lineLimit(1)
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

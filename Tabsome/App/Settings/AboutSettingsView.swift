import SwiftUI

/// Settings › About (PLAN.md §7 Phase 6): the version, Report a Problem… (Phase 7a), and
/// acknowledgements. Check for Updates… arrives with Sparkle in Phase 7c.
struct AboutSettingsView: View {
    let model: AppModel
    @State private var reporting = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text(Brand.name).font(.title2.bold())
                    Text(version).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Tabs for any window, from any app.")
                        .foregroundStyle(.secondary)
                    Button("Report a Problem…") { reporting = true }
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Acknowledgements") {
                ForEach(Acknowledgement.all) { AcknowledgementRow(item: $0) }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .sheet(isPresented: $reporting) { ProblemReportView(model: model) }
    }
}

/// Open-source code Tabsome includes, with the license that asks to be shown.
struct Acknowledgement: Identifiable {
    let name: String
    let author: String
    let url: URL
    let license: String
    var id: String { name }

    static let all = [
        Acknowledgement(name: "KeyboardShortcuts", author: "Sindre Sorhus",
                        url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!,
                        license: mit(holder: "Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)")),
    ]

    static func mit(holder: String) -> String {
        """
        MIT License

        Copyright (c) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}

/// The name and author, with the license in a sheet.
private struct AcknowledgementRow: View {
    let item: Acknowledgement
    @State private var showsLicense = false

    var body: some View {
        LabeledContent {
            HStack {
                Link("Website", destination: item.url)
                Button("License") { showsLicense = true }
            }
        } label: {
            Text(item.name)
            Text("by \(item.author)")
        }
        .sheet(isPresented: $showsLicense) {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.name).font(.headline)
                ScrollView {
                    Text(item.license)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Done") { showsLicense = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 460, height: 360)
        }
    }
}

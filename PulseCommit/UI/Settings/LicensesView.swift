import SwiftUI

struct LicensesView: View {
    static let zipFoundationLicense: String = """
MIT License

Copyright (c) 2017-2024 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                PCCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ZIPFoundation")
                            .font(.pcBodySemibold)
                            .foregroundStyle(Theme.text)
                        Text("MIT · github.com/weichsel/ZIPFoundation")
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.dim)
                        Spacer().frame(height: 4)
                        PCCodeBlock(content: LicensesView.zipFoundationLicense)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        Text("$ cat LICENSES")
            .font(.pcCaptionMono)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

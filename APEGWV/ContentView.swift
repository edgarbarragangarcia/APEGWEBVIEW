//
//  ContentView.swift
//  APEGWV
//
//  Created by Edgar A. Barragán G. on 15/01/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://apegwv.vercel.app/")!)
            .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}

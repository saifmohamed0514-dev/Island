//
//  EmptyState.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI

struct EmptyStateView: View {
    var message: String
    @State private var isVisible = true
    
    var body: some View {
        HStack {
            Image(systemName: "tray").font(.system(size:28,weight:.light)).foregroundStyle(.secondary)
            Text(message)
                .font(.system(size:14))
                .foregroundColor(.gray)
        }.transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)))) // Smooth animation
    }
}

#Preview {
    EmptyStateView(message: "Nothing here yet")
}

import SwiftUI

struct SplashScreenView: View {
    @Binding var isFinished: Bool
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var textOffset: CGFloat = 20
    @State private var shimmerOffset: CGFloat = -200
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0.0
    @State private var pulseScale: CGFloat = 1.0
    
    // Color transition layers (opacity-based for real animation)
    @State private var fuchsiaOpacity: Double = 1.0
    @State private var midOpacity: Double = 0.0
    
    // Colors
    let fuchsia = Color(red: 236/255, green: 0/255, blue: 140/255)
    let midTone = Color(red: 60/255, green: 10/255, blue: 50/255) // dark magenta
    let loginGreen = Color(red: 6/255, green: 18/255, blue: 12/255)
    
    var body: some View {
        ZStack {
            // Layer 1 (bottom): Green — always visible
            loginGreen.edgesIgnoringSafeArea(.all)
            
            // Layer 2 (middle): Dark magenta — fades in then out
            midTone
                .edgesIgnoringSafeArea(.all)
                .opacity(midOpacity)
            
            // Layer 3 (top): Fuchsia — fades out first
            fuchsia
                .edgesIgnoringSafeArea(.all)
                .opacity(fuchsiaOpacity)
            
            // Subtle radial glow
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.12 * fuchsiaOpacity),
                    Color.clear
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 350
            )
            .edgesIgnoringSafeArea(.all)
            
            // Decorative ring
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.0)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 240, height: 240)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            
            // Pulse ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: 280, height: 280)
                .scaleEffect(pulseScale)
                .opacity(max(0, 2 - Double(pulseScale)))
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo
                Image("APEGLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                
                // App Name
                Text("APEG")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(8)
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                    .padding(.top, 20)
                
                // Subtitle
                Text("GOLF COMMUNITY")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.85))
                    .tracking(4)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                    .padding(.top, 5)
                
                Spacer()
                
                // Bottom shimmer bar
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 3)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.9), Color.clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 40, height: 3)
                        .offset(x: shimmerOffset)
                        .mask(
                            Capsule()
                                .frame(width: 120, height: 3)
                        )
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            // Logo entrance
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            // Ring reveal
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                ringScale = 1.0
                ringOpacity = 1.0
            }
            
            // Text fade in
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                textOpacity = 1.0
                textOffset = 0
            }
            
            // Pulse
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulseScale = 1.6
            }
            
            // Shimmer
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.8)) {
                shimmerOffset = 200
            }
            
            // === COLOR DEGRADATION SEQUENCE ===
            
            // Phase 1 (2.0s): Show mid-tone layer, start fading fuchsia
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 1.2)) {
                    midOpacity = 1.0
                    fuchsiaOpacity = 0.0
                }
            }
            
            // Phase 2 (3.0s): Fade out mid-tone to reveal green underneath
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 1.2)) {
                    midOpacity = 0.0
                }
            }
            
            // Fade out content
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    logoScale = 1.1
                    logoOpacity = 0
                    textOpacity = 0
                    ringOpacity = 0
                }
            }
            
            // Dismiss when fully green
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                isFinished = false
            }
        }
    }
}

#Preview {
    SplashScreenView(isFinished: .constant(true))
}

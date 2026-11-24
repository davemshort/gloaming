# Project: Open-Source Dynamic Wallpaper Engine for macOS

## Objective

Design and develop a native, open-source macOS application that generates beautiful, continuously evolving animated desktop wallpapers using Apple's Metal graphics framework.

The application should produce fluid, atmospheric gradients with organic movement, customizable colors, and optional environmental awareness.

The goal is to create a lightweight, polished alternative to commercial dynamic wallpaper applications, with an emphasis on native macOS integration, efficiency, reliability, and user control.

This must be an original implementation, not a reproduction of another application's proprietary code, shaders, or visual assets.

## 1. Technology Stack

Use the following technologies:

- **Language:** Swift
- **Interface:** SwiftUI, with AppKit integration where necessary
- **Rendering:** Metal and Metal Shading Language
- **Architecture:** MVVM or another appropriately lightweight, modular architecture
- **Persistence:** UserDefaults or a suitable native preferences mechanism
- **Weather:** Apple WeatherKit, if practical and available
- **Build system:** Xcode project or Swift Package Manager, as appropriate
- **Minimum macOS version:** macOS 14 (Sonoma)
- **Distribution:** Direct-download application, independent of the Mac App Store
- **License:** MIT

Avoid Electron, embedded browsers, third-party UI frameworks, and unnecessary dependencies.

Favor native Apple frameworks and APIs.

## 2. Core Wallpaper Engine

Implement a GPU-accelerated wallpaper renderer using Metal.

### Visual Characteristics

The wallpaper should feature:

- Smooth, continuously evolving color gradients
- Organic, fluid-like movement
- Soft transitions between colors
- Subtle diffusion and blending
- Optional film grain or texture
- No obvious animation loops
- No abrupt transitions or visible rendering artifacts

The visual appearance should feel atmospheric, understated, and elegant.

Avoid excessive motion, distracting patterns, and visually harsh effects.

### Rendering Requirements

- Perform visual computations primarily on the GPU.
- Minimize CPU usage.
- Avoid unnecessary memory allocations during rendering.
- Use frame pacing appropriate for desktop wallpaper animation.
- Support configurable frame rates, including 15, 30, and 60 FPS.
- Support Retina and non-Retina displays.
- Handle changes in display resolution and scaling.
- Avoid unnecessarily rendering at full native resolution when lower-resolution rendering with high-quality upscaling is visually equivalent.
- Ensure smooth transitions when changing palettes or settings.

Design the rendering engine so additional shader effects can be introduced without rewriting the application.

## 3. macOS Desktop Integration

The application must function as a desktop wallpaper rather than a conventional application window.

Investigate supported macOS APIs and practical approaches for displaying animated content at the desktop wallpaper level.

Requirements:

- Render behind desktop icons.
- Remain behind normal application windows.
- Support Mission Control and Spaces.
- Support multiple monitors.
- Support fullscreen applications without interfering with their behavior.
- Handle display connection and disconnection.
- Handle resolution changes.
- Restore wallpaper functionality after sleep and wake.
- Avoid interfering with Finder or other desktop services.

**Important:** Do not assume that macOS exposes a public API for continuously animated third-party wallpapers.

Before implementing the desktop integration layer:

1. Research available public APIs and their limitations.
2. Evaluate AppKit desktop-level windows and their interaction with Finder, Spaces, and Stage Manager.
3. Determine whether the desired behavior is achievable without private APIs.
4. Document compatibility limitations and expected failure modes.
5. Recommend the most reliable architecture.

Do not use undocumented APIs without explicitly identifying them and explaining the consequences.

If true wallpaper-level integration is not possible through supported APIs, implement the closest reliable alternative and document the tradeoffs.

## 4. Appearance and Customization

Provide several built-in color palettes, such as:

- Aurora: Deep blue, violet, teal
- Sunset: Orange, pink, purple
- Ocean: Navy, cyan, turquoise
- Ember: Burgundy, amber, dark red
- Forest: Deep green, sage, muted gold
- Monochrome: Black, charcoal, silver

Allow users to:

- Select a preset palette.
- Create custom palettes.
- Add, remove, and reorder colors.
- Adjust animation speed.
- Adjust gradient complexity.
- Adjust color blending intensity.
- Adjust grain intensity.
- Configure brightness and saturation.
- Randomize palettes.
- Save and delete custom presets.

Settings should update the wallpaper immediately without restarting the renderer.

## 5. Time-Aware Appearance

Implement optional automatic palette adjustments based on local time.

Support:

- Morning
- Daytime
- Sunset
- Evening
- Night

Transitions should occur gradually rather than abruptly.

Allow users to configure:

- Automatic time-based adjustments
- Fixed palettes
- Custom transition times
- Nighttime brightness reduction
- Automatic light/dark appearance synchronization

Prefer calculating solar events locally using Core Location and an appropriate algorithm, rather than requiring a continuous network connection.

Time-aware behavior must remain functional without internet access.

## 6. Weather Integration

Design an optional weather-aware rendering system.

Potential effects:

- Rain: Subtle streaking or ripple-like distortion
- Snow: Slow, soft particle movement
- Fog: Reduced contrast and diffuse color blending
- Wind: Changes in gradient movement direction and velocity
- Clear skies: Minimal atmospheric distortion
- Cloud cover: Muted brightness and saturation

Requirements:

- Weather integration must be optional.
- The wallpaper must work without WeatherKit credentials.
- Avoid continuous weather polling.
- Cache weather conditions appropriately.
- Minimize location requests.
- Respect macOS privacy permissions.
- Never transmit location data to third-party analytics services.

Weather effects should remain subtle and should not compromise the application's minimalist appearance.

Keep weather integration modular so it can be disabled at build time if necessary.

## 7. Performance and Power Management

Efficiency is a primary design objective.

Implement:

- Configurable FPS limits
- Automatic throttling when running on battery
- Automatic suspension during Low Power Mode
- Suspension when displays sleep
- Reduced rendering when the desktop is not visible, where reliably detectable
- GPU resource reuse
- Efficient shader pipelines
- Proper cleanup of Metal resources
- Recovery from display and graphics device changes

Provide a preference to override battery-related throttling.

Avoid continuously polling system state when event-driven notifications are available.

### Performance Measurement

Add development diagnostics for:

- Current FPS
- Average frame time
- CPU utilization
- GPU utilization, where measurable through supported APIs
- Memory usage
- Current render resolution
- Active display count
- Renderer suspension state

Do not fabricate unavailable metrics. Clearly distinguish measured values from estimates.

## 8. Menu Bar Application

Build a lightweight macOS menu bar interface.

The application should run without a persistent Dock icon by default.

Menu bar functionality:

- Enable/disable wallpaper
- Select a palette
- Pause/resume animation
- Adjust animation speed
- Open Settings
- Display basic renderer status
- Check for updates
- Quit application

Use SwiftUI for the settings interface and AppKit where necessary.

Follow macOS Human Interface Guidelines.

## 9. Settings Interface

Create a clean, native settings window with sections for:

**Appearance**
- Palette selection
- Custom colors
- Animation controls
- Grain and brightness

**Automation**
- Time-aware appearance
- Weather integration
- Transition behavior

**Displays**
- Available monitors
- Independent wallpaper configuration
- Resolution scaling
- Frame-rate preferences

**Performance**
- Battery behavior
- FPS limits
- Power-saving settings
- Diagnostic information

**General**
- Launch at login
- Menu bar behavior
- Update preferences
- About and license information

Use native SwiftUI controls and avoid unnecessary visual complexity.

## 10. Multi-Monitor Support

Detect connected displays and maintain their configurations.

Support:

- Independent wallpapers per monitor
- Shared palettes across monitors
- Independent animation parameters
- Different display resolutions and scaling factors
- Display hot-plugging
- Stable display identification where possible

Avoid launching redundant rendering processes.

Investigate whether a shared Metal device and rendering infrastructure can efficiently support multiple displays.

## 11. Privacy and Security

The application must be privacy-respecting by design.

Requirements:

- No analytics or telemetry
- No advertising
- No user accounts
- No unnecessary network requests
- No collection of personal information
- No background services beyond what is necessary
- No privileged helper or root permissions
- No private API dependencies unless explicitly approved

All user preferences should be stored locally.

Document every required macOS permission and its purpose.

## 12. Open-Source Project Structure

Organize the code into logical components.

Suggested structure:

```text
DynamicWallpaper/
├── App/
├── Desktop/
├── Rendering/
│   ├── Metal/
│   ├── Shaders/
│   └── Effects/
├── Models/
├── Services/
│   ├── Weather/
│   ├── Time/
│   ├── Displays/
│   └── Power/
├── Settings/
├── Resources/
│   └── Palettes/
├── Tests/
├── Documentation/
├── README.md
├── CONTRIBUTING.md
└── LICENSE
```

Adjust the structure where technically justified.

Maintain clear separation between:

- Rendering
- Desktop integration
- Application lifecycle
- Settings
- Environmental services
- User interface

Use Swift concurrency appropriately and ensure UI updates occur on the correct actor.

## 13. Testing and Reliability

Implement automated tests where practical.

Test:

- Palette serialization
- Settings persistence
- Time-based color transitions
- Display configuration changes
- Renderer lifecycle management
- Sleep/wake recovery
- Power management decisions
- Weather-service fallback behavior

Provide a manual test checklist for:

- Mission Control
- Spaces
- Stage Manager
- Fullscreen applications
- Multiple monitors
- Retina scaling
- Login and logout
- Sleep and wake
- Battery and AC transitions

Ensure the application fails gracefully and can restore the user's previous desktop configuration where applicable.

## 14. Distribution and Documentation

Prepare the project for public GitHub distribution.

Include:

- Complete README
- Build instructions
- Minimum system requirements
- Architecture overview
- Configuration documentation
- Screenshots or demo recording instructions
- Known limitations
- Contribution guidelines
- MIT license
- GitHub Actions build and test workflow

Document the process for signing and notarizing macOS builds.

Do not require signing credentials for local development.

## 15. Development Strategy

Implement the project incrementally.

### Phase 1: Technical Feasibility

Before building the full application:

1. Investigate macOS desktop integration.
2. Create a minimal AppKit prototype that displays animated Metal content at the desktop level.
3. Verify behavior with Finder desktop icons.
4. Test basic Mission Control and Spaces behavior.
5. Document what works, what fails, and which APIs are involved.

**Do not proceed with the complete application until the desktop integration approach is validated or its limitations are clearly established.**

### Phase 2: Rendering Engine

Implement:

- Metal rendering pipeline
- Initial fluid gradient shader
- Animation timing
- Palette interpolation
- Adjustable animation parameters
- Basic performance measurements

### Phase 3: Application Interface

Implement:

- Menu bar application
- Settings window
- Palette management
- Settings persistence
- Start/stop controls

### Phase 4: System Integration

Implement:

- Multi-monitor support
- Power management
- Sleep/wake handling
- Launch at login
- Display change handling

### Phase 5: Environmental Features

Implement:

- Time-aware palettes
- Solar event calculations
- Optional weather integration
- Atmospheric effects

### Phase 6: Release Preparation

Implement:

- Automated tests
- Documentation
- Build workflow
- Performance profiling
- Packaging and release instructions

## 16. Development Expectations

Act as an experienced macOS platform engineer with expertise in Swift, AppKit, SwiftUI, Metal, and graphics performance.

Prioritize:

1. Correctness
2. Native macOS behavior
3. Reliability
4. Performance and battery efficiency
5. Visual quality
6. Maintainability
7. Feature completeness

Avoid unnecessary abstractions, speculative frameworks, and overengineering.

Use established Apple APIs and document any platform limitations.

Do not silently substitute mock implementations for working functionality.

Do not claim that functionality has been tested unless tests were actually executed.

When an architectural decision involves meaningful tradeoffs, explain the options and recommend an approach.

## Initial Task

**Begin with Phase 1 only.**

Research and evaluate the technical feasibility of implementing an animated desktop wallpaper on macOS 14 and later using public APIs.

Produce:

1. A technical feasibility assessment
2. Recommended architecture
3. Identified macOS limitations
4. Minimal proof-of-concept implementation
5. Instructions for building and running the prototype
6. A test plan for desktop integration

Do not begin implementing the complete application until the feasibility assessment and proof of concept have been reviewed.
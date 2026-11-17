> ❤️ **A special thank you to the original PlayTorrio creators**
>
> PlayTorrio Enhanced exists thanks to **Ayman**, the original creator of PlayTorrio V3, and **[hendrayoga](https://github.com/hendrayoga/ptv3)**, whose fork provided the foundation for our work.
>
> Their contributions made this project possible. We're grateful for the time, effort, and creativity they put into building PlayTorrio and making it available to the community.
>
> This fork builds upon their work with new features, improvements, and a stronger focus on everyday usability.

---

# 🎬 PlayTorrio Enhanced

### Same foundation. A whole new level of control.

**Better playback. Smarter discovery. Personalized entertainment. Your experience, your way.**

PlayTorrio Enhanced is a community-driven fork focused on making the original PlayTorrio more comfortable, reliable, and customizable.

We've invested in the features that make a difference every day, from making dialogue easier to hear and keeping subtitles in sync to finding better recommendations and carrying your watch progress between devices.

## ✨ What's new in our fork?

### 🌙 1. Night Mode: Hear the dialogue, not just the explosions

Ever turned up the volume to hear someone talking, only to get blasted by an action scene seconds later?

Our enhanced **Night Mode** helps balance loud and quiet audio, making movies more comfortable to watch, especially at night.

- Reduce sudden jumps in volume.
- Make quieter dialogue easier to follow.
- Enjoy a more consistent listening experience.
- Native audio processing on supported platforms.

**Less volume juggling. More enjoying the movie.**

### 💬 2. Automatic subtitle synchronization

Subtitles appearing too early or too late can ruin a great movie.

We've introduced speech-assisted subtitle synchronization that helps align subtitles with what you're hearing.

- Automatically detect and correct supported subtitle timing mismatches.
- Use speech-based alignment on supported devices.
- Keep manual subtitle adjustment available.
- Reduce the need to constantly tweak subtitle delays.

Just choose your subtitles and let PlayTorrio help keep everything in sync.

*Automatic alignment depends on the platform, audio source, and subtitle availability.*

### 🎞️ 3. Improved native playback

We've put significant effort into improving how PlayTorrio actually plays your content.

Our enhanced playback system focuses on stability, smoothness, and reliable media handling.

- Improved native MPV and FFmpeg integration.
- Hardware-assisted video decoding where supported.
- Better handling of different media formats.
- Improved audio and video synchronization.
- Additional safeguards against playback failures.

The goal is simple: **Press Play and enjoy your content with fewer interruptions.**

### 🔊 4. Audio presets for different listening preferences

Not everyone wants the same sound.

We've added four simple audio presets that let you adjust the listening experience without complicated settings.

| Preset | Best for |
|---|---|
| **Flat** | Original, balanced sound |
| **Dialogue** | Bringing voices forward |
| **Cinema** | Fuller movie sound |
| **Warm** | Softer, warmer listening |

Whether you're using headphones, speakers, or watching late at night, choose what sounds best to you.

### ⏭️ 5. Automatic intro skipping

Tired of watching the same opening sequence every episode?

PlayTorrio can now automatically skip supported intros when reliable timing information is available.

- Recognizes supported episode intro markers.
- Uses a short countdown before skipping.
- Avoids guessing when timing information is unreliable.
- Preserves manual skipping where automatic skipping isn't appropriate.

Perfect for those long TV marathons.

### 🔄 6. Better playback interruption recovery

A brief connection problem shouldn't always mean starting over.

We've improved playback recovery to help the player handle interruptions more gracefully.

- Better recovery after temporary network interruptions.
- Improved handling when resuming paused streams.
- Additional safeguards for problematic playback sources.
- Better detection of playback issues.

These changes aim to reduce unnecessary restarts and make longer viewing sessions more dependable.

### 🔎 7. Advanced Discover: Find exactly what you're in the mood for

Sometimes you know what kind of movie you want, but not its name.

Our new **Advanced Discover** experience helps you find content using more specific preferences.

You can explore by:

- **Genre:** Action, comedy, horror, thriller, science fiction, and more.
- **Release year:** Discover classics or recent releases.
- **Country:** Find productions from different countries.
- **Original language:** Explore international movies and television.
- **Ratings:** Look for highly rated titles.
- **Popularity:** See what's trending or widely watched.

Want a highly rated Korean thriller from the 2010s? Or a Japanese science fiction series?

Advanced Discover makes finding those titles much easier.

### 🧠 8. Recommendations that feel more personal

We've expanded the recommendation system to help you find content related to your own tastes.

Rather than relying only on generic popularity lists, PlayTorrio can use information from supported connected libraries to improve suggestions.

- Personalized recommendations from Trakt and Simkl.
- Better matching of related movies and series.
- Improved discovery based on available viewing history.
- More relevant content suggestions on your Home screen.

The more useful information your connected services provide, the better PlayTorrio can tailor your discovery experience.

### 🏠 9. Personalized catalog sections

Your Home screen shouldn't look exactly the same as everyone else's.

We've introduced additional catalog sections that can reflect your connected libraries, interests, and viewing activity.

Discover more content without having to search for it every time.

Personalized sections can help surface:

- Recommendations related to titles you've watched.
- Suggestions drawn from connected libraries.
- Content from your preferred discovery sources.
- More relevant movies and series alongside your existing catalogs.

### 🎨 10. Customize your Home screen

We believe your entertainment app should fit the way you use it.

Our fork introduces additional Home customization options, giving you more control over what appears and where.

- Rearrange Home sections.
- Choose which supported sections are displayed.
- Customize catalog presentation.
- Adjust supported interface and appearance preferences.

**Less clutter. More of what matters to you.**

### ☁️ 11. Keep your library synchronized across devices

Start watching on one device and continue on another.

We've added optional **GitHub-based cloud synchronization** to help keep your PlayTorrio library consistent across supported devices.

Synchronize:

- **My List:** Your saved movies and shows.
- **Continue Watching:** Your playback progress.
- **Watched History:** Your viewing activity.
- **Supported settings:** Selected preferences and portable configuration.

Unlike a service that requires a centrally hosted PlayTorrio account, this system lets you use a GitHub repository that you configure and control.

We've also added handling for changes made on multiple devices to reduce the chance of losing your library updates.

*Requires initial configuration of GitHub synchronization.*

### ⚡ 12. Smarter cached source detection

When you're using a supported debrid provider, finding an already cached source can make playback more convenient.

We've improved how PlayTorrio evaluates stream availability and readiness.

- Better checks for cached source availability.
- Improved handling of source readiness information.
- More useful source prioritization.
- Safer behavior when cache information is unavailable.

Instead of treating every result as equally ready to play, PlayTorrio can make better use of the information provided by your connected services.

### ⚙️ 13. Easier settings backup and recovery

Customizing an app takes time. You shouldn't have to repeat everything when moving devices or recovering a configuration.

Our fork introduces improved settings portability and recovery options.

- Export supported settings.
- Import saved configurations.
- Recover selected preferences and addon configurations.
- Improve recovery from incomplete or older settings data.

Set up PlayTorrio the way you like, and keep a backup of your configuration.

---

## 🧩 Other improvements

We've also made many smaller improvements that help everything work more reliably behind the scenes.

| Area | What's improved |
|---|---|
| **Stremio addons** | Better addon compatibility, catalog handling, independent metadata recovery, and improved protocol support |
| **Source selection** | Advanced filtering, preferred audio language, addon priorities, and three-level sorting |
| **Live TV** | Better handling of Stremio live channels and programme metadata |
| **Subtitles** | Expanded subtitle controls, timing correction, and addon compatibility |
| **Discovery** | Streaming Networks browsing, original language information, cast discovery, and filmographies |
| **Metadata** | Improved validation, recovery, and optional TVDB series information |
| **Library integration** | Enhanced watched history, Trakt and Simkl synchronization |
| **TorBox** | Simplified account configuration and key verification |
| **Diagnostics** | Optional, privacy-conscious playback troubleshooting |
| **Platform improvements** | Additional iOS and Windows playback enhancements |

## 🛠️ Want to know more?

PlayTorrio Enhanced includes many technical improvements that don't need to clutter the main README.

More detailed documentation can cover the player architecture, subtitle synchronization, streaming preferences, addon compatibility, caching behavior, cloud synchronization, and platform-specific features.

For developers and advanced users, these implementation details will be documented separately from the main feature overview.

---

## 🚀 An actively evolving fork

PlayTorrio Enhanced is an ongoing project focused on making the original PlayTorrio experience better with every update.

We're continuing to improve playback reliability, subtitle synchronization, discovery, source selection, and cross-device convenience.

**Our goal isn't to replace what made PlayTorrio great. It's to make using it even better.**

Some enhancements depend on your platform, connected services, configuration, or installed version. Newly committed features may not yet be included in the latest downloadable build.

---

## ❤️ Credits and acknowledgments

**Original PlayTorrio V3:** Ayman

**Upstream fork:** [hendrayoga/ptv3](https://github.com/hendrayoga/ptv3)

**Enhanced fork:** [mghazalyh/ptv3](https://github.com/mghazalyh/ptv3)

A special thank you to the original developers and everyone contributing to the project's continued evolution.

**License:** [GNU GPL v3.0](LICENSE)

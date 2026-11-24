package io.github.v3ai.music

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity keeps the player connected to the background media service,
// so music continues with the screen off or the app closed.
class MainActivity : AudioServiceActivity()

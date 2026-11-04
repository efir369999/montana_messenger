import Foundation

/// MONTANA'S LETTERS OF A GAME (docs/APPS-API.md, rule 3 and slice S4b): the reader of a game's letters this edition carries, for the
/// app and the notification extension alike -- the edition's one file both targets hold, since the extension carries no door of an
/// application. An edition that carries no game says nil, and a game's letter is then the words it shows.
enum MTEditionLetters {
    static let game: MTGameLetters? = MTChessLetters()
}

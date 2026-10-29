/// The Firebase Realtime Database that carries phone rooms, e.g.
/// "https://quizinho-default-rtdb.europe-west1.firebasedatabase.app".
/// Empty = playing on other phones is switched off.
const roomsDatabaseUrl = 'https://quizinho-8022c-default-rtdb.europe-west1.firebasedatabase.app';

/// Where a phone without the app joins: the web build, with ?join=CODE.
const joinPageUrl = 'https://uncleanthonys.github.io/quizinho/';

bool get roomsEnabled => roomsDatabaseUrl.isNotEmpty;

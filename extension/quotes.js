// Original Habit Gate encouragement. Chosen once per page; no requests or timers.
export const focusQuotes = Object.freeze([
  'Small steps still move you forward.',
  'Give the next few minutes to what matters.',
  'You do not need to finish everything. Begin with one thing.',
  'A little attention today makes room for tomorrow.',
  'Let the next small action be enough to begin.',
  'Your attention is worth protecting.',
  'You have time for one meaningful step.',
  'Make a little room for the person you want to become.',
  'Start gently. Keep going.',
  'Choose your next action with care.',
  'Progress can be quiet and still be real.',
  'The feed can wait. This moment is yours.'
]);
export function randomFocusQuote() {
  return focusQuotes[Math.floor(Math.random() * focusQuotes.length)];
}

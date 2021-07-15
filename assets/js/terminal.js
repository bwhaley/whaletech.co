import { Terminal } from 'xterm';
import LocalEchoController from 'local-echo';

// Start an xterm.js instance
const term = new Terminal();
term.open(document.getElementById('terminal'));

// Create a local echo controller (xterm.js v3)
const localEcho = new LocalEchoController(term);
// Create a local echo controller (xterm.js >=v4)
const localEcho = new LocalEchoController();
term.loadAddon(localEcho);

// Read a single line from the user
localEcho.read("~$ ")
    .then(input => alert(`User entered: ${input}`))
    .catch(error => alert(`Error reading: ${error}`));
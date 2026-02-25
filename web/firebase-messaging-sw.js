importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
    apiKey: 'AIzaSyBhDwUY9ZU7KrgQSzREW8Dl8QyombvcIqc',
    appId: '1:356056697601:web:e341b870d1384077c42900',
    messagingSenderId: '356056697601',
    projectId: 'shapeos-smarthome',
    authDomain: 'shapeos-smarthome.firebaseapp.com',
    storageBucket: 'shapeos-smarthome.firebasestorage.app',
    measurementId: 'G-NG6QKED27T',
});

const messaging = firebase.messaging();
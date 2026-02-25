const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.securityAlertTrigger = functions.database
  .ref("/alerts/{alertType}")
  .onUpdate(async (change, context) => {

    const before = change.before.val();
    const after = change.after.val();

    // Only send when false -> true
    if (!before && after === true) {

      const alertType = context.params.alertType;

      const title = `${alertType.toUpperCase()} ALERT`;
      const body = `Security issue detected: ${alertType}`;

      const usersSnapshot = await admin.firestore()
        .collection("users")
        .get();

      const promises = [];

      usersSnapshot.forEach(doc => {
        const token = doc.data().fcmToken;

        if (token) {
          const message = {
            token: token,
            notification: {
              title: title,
              body: body
            },
            android: {
              priority: "high",
              notification: {
                sound: "default"
              }
            }
          };

          promises.push(admin.messaging().send(message));
        }
      });

      return Promise.all(promises);
    }

    return null;
});
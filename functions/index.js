const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.securityAlertTrigger = functions.database
  .ref("/alerts/{alertType}")
  .onUpdate(async (change, context) => {

    const before = change.before.val();
    const after = change.after.val();

    const alertType = context.params.alertType;

    // 🚫 Motion sensor was decommissioned — never push a
    //    motion notification even if a stale value flips
    //    in the database.
    if (typeof alertType === "string" &&
        alertType.toLowerCase() === "motion") {
      return null;
    }

    // Only send when false -> true
    if (!before && after === true) {

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
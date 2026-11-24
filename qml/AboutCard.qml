// "About Facteur": Facteur is the display name of fili-mail (an alias); the kit's card shows the icon, the line saying what it
// is and the rows the application reports (aboutRows).
import QtQuick
import Fili.UI
import Fili.Mail

FiliAboutCard {
    appName: "Facteur"
    tagline: Facteur.tr("The mail client of Filigrane")
    iconSource: "qrc:/qt/qml/Fili/Mail/data/icons/hicolor/scalable/apps/fili-mail.svg"
}

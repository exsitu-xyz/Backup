/* ***********************************************************
 Pour le projet Backup de Exsitu, code du module "video slave"
 Réception de messages OSC envoyés par pure data 
 Et affichage des infos tirées de la base de données en conséquence
 Quimper, La Baleine, novembre 2019 / pierre@lesporteslogiques.net
 processing 3.5.3 @ kirin
 doc : https://exsitu.xyz/doku.php?id=prod:creation:meta-projet:back-up
 
 version du futuuuuur :
   * TODO images impressionistes à droite
     Principe : pour chaque id, un dossier comprenant entre 0 et 100 images 
     En prendre 2/3/4 les assembler en fondu
   * TODO : faire varier les dimensions de la fenêtre avec le message OSC /video/param
   * TODO ajouter un try/catch sur les messages OSC reçus, on ne sait jamais...
   * OK ds la version 3 : changer la méthode des fondus, elle n'est pas fluide
     A remplacer par image + cache noir semi opaque selon l'étape
   * TODO : optimiser les affichages, ça ne sert à rien de réafficher si pas de changement...
 
 version 003 (novembre 2019) :
   * OK affichage des coordonnées, depuis coord GPS vers projection Mercator
   * OK nouveaux formats de coordonnées pour 2 types de messages : 
     * video/shape/ ID level fadein hold fadeout (en ms pour ces 3 dernières valeurs)
     * video/param/ width height 
   * OK fondus : fadein : augmentation de l'opacité, fadeout : vers le noir
   * OK intégrer nouvelle base de données (fichier CSV)
   * OK noCursor();
   * OK augmenter taille texte
   
 version 002 (juillet 2019) :
   * définition rpi / videoprojection HDMI 720p : 1280 x 720
   * mise en page : 2 carrés de 640x640 côte à côte
   * chargement de l'image dynamique correspondant à l'objet
   * "monophonie" = un seul objet à la fois

 *********************************************************** */
 
// Infos de DEBUG si je veux **********************************
boolean DEBUG        = true;    // affichage sur la fenêtre de rendu et sur la console
boolean DEBUG_NO_OSC = false;   // permet de tester, SANS OSC, si nécessaire! nécessite aussi que DEBUG = true
long DEBUG_NO_OSC_last = -4000; // temps arbitraire pour tester sans réception

// Déclaration des objets OSC *********************************
import oscP5.*;
import netP5.*;
OscP5 oscP5;
NetAddress myRemoteLocation;

// Initialisation des variables  ******************************
float r_id      = 1;
float r_level   = 1;
float r_fadein  = 800;
float r_hold    = 3000;
float r_fadeout = 1000;
float r_width   = 0;
float r_height  = 0;

boolean nouvelle_reception = true;
int id          = int(r_id);

// Stockage des photos d'objets *******************************
String dossier_images = "objets-geocyclab"; // à placer dans le dossier data
PImage image_objet;

// Déclaration de la base de données ***************************
String base_objets = "geocyclab-datas.csv";   // à placer dans le dossier data
Table objet;

// Affichage des coordonnées ***********************************
MercatorMap mm;
float lat, lon;     // coordonnées de l'objet dans le système GPS (WGS 84)
PVector pixel_loc;  // coordonnées de l'objet sur la fond de carte en pixels
PVector planisphere_start; // coordonnées d'affichage de la carte
PImage planisphere;

// Divers assets ***********************************************
PFont police;
int x_start, y_start; // variables utilisés pour l'affichage des données

// Variables utilisées pour l'animation ************************
int old_id = -1;
float fps = 60;            // Frames par secondes, mis à jour dynamiquement ci-dessous
float objet_start;         // en millisecondes, moment d'apparition de l'objet
float opacite_cache = 255; // valeur d'opacité du cache noir utilisé pour les fondus



void setup() {
  size(1280, 720, P3D);
  noCursor(); // Pour éviter qu'un curseur de souris se ballade ...
  frameRate(30);
  
  // Mettre en place la communication OSC
  oscP5 = new OscP5(this, 8003); // écoute des messages OSC sur le port 8003
  myRemoteLocation = new NetAddress("127.0.0.1", 12000);

  // Charger une image
  chargerImageObjet(dossier_images, int(r_id));
  
  // Charger la police 
  police = loadFont("BitstreamVeraSansMono-Roman-32.vlw");
  
  // Charger le fond de carte
  planisphere = loadImage("mercator_540x288.png"); 
  planisphere_start = new PVector(690, 382);
  // définir l'objet de conversion coord. géoloc -> pixels
  mm = new MercatorMap(540, 288, 75, -60, -180, 180);
  
  // Charger la base de données des objets
  objet = loadTable("data/" + base_objets, "header");
  if (DEBUG) println(objet.getRowCount() + " lignes dans la base"); 
  
  background(0);
}



void draw() {
  
  // Quel est le framerate réel ? On l'utilisera pour le calcul des fondus
  fps = frameRate;
  
  // Recouvrir le texte de noir à chaque frame
  noStroke();
 // fill(0);
  rect(690, 0, 590, height - planisphere_start.y + 10);
  
  // DEBUG
  if ( (DEBUG_NO_OSC) && (millis() - DEBUG_NO_OSC_last > 4000) ) {
    nouvelle_reception = true;
    DEBUG_NO_OSC_last = millis();
    r_id = random(1001);
  }
  
  // Si changement d'objet
  if (nouvelle_reception) {
    id = int(r_id);
    if (id < 1) id = 1;
    if (id > 1000) id = 1000;
    chargerImageObjet(dossier_images, id);
    objet_start = millis();
    opacite_cache = 255;
    //calculerFondus();
    nouvelle_reception = false;
  }

  // Première partie (gauche) : afficher l'image *************************************
  // soit on est en fadein, soit on est en hold, soit on est en fadeout, soit on clean l'affichage!
  String debug_state = " stable ";
 
  if (millis() - objet_start < r_fadein) {                                                                        // fade in time
    // Calcul des etapes restantes
    float etapes = ( (objet_start + r_fadein) - millis() ) / (1000 / fps);
    // Calcul de la nouvelle opacité du cache
    opacite_cache = opacite_cache - (opacite_cache / etapes);
    image(image_objet, 0, 40, 640, 640);
    fill(0, opacite_cache);
    rect(0, 40, 640, 640);
    debug_state = " fadein ";
  }
  if ((millis() - objet_start > r_fadein) && (millis() - objet_start < r_fadein + r_hold)) {                      // hold time
    // rien ne bouge!
    opacite_cache = 0;
    image(image_objet, 0, 40, 640, 640); 
    debug_state = " hold ";
  }
  if ((millis() - objet_start > r_fadein + r_hold) && (millis() - objet_start < r_fadein + r_hold + r_fadeout)) { // fade out time
    noStroke();
    // Calcul des etapes restantes
    float etapes = ( (objet_start + r_fadein + r_hold + r_fadeout) - millis() ) / (1000 / fps);
    // Calcul de la nouvelle opacité du cache
    opacite_cache = opacite_cache + (255 / etapes);
    image(image_objet, 0, 40, 640, 640);
    fill(0, opacite_cache);
    rect(0, 40, 640, 640);
    debug_state = " fadeout ";
  }
  if (millis() - objet_start > r_fadein + r_hold + r_fadeout) {                                                   // en attente !
    opacite_cache = 255;
    debug_state = " clean ";
  }
  
  if (DEBUG) { // DEBUG : Affichage écran des étapes de fondu ********************
    textFont(police, 12);
    fill(0);
    rect(0, height - 20, width, 20);
    fill(150);
    text(debug_state, 0, height - 4);
  }
  
  if (DEBUG) { // DEBUG : Affichage des valeurs reçues par OSC *******************
    fill(0);
    rect(0, 0, width, 40);
    fill(150);
    noStroke();
    textFont(police, 12);
    text("DEBUG : fps : " + int(frameRate) + " -- /video/shape id : " + int(r_id) + ", level : " + r_level 
         + ", fadein : " + int(r_fadein) + ", hold : " + int(r_hold) + ", fadeout : " + int(r_fadeout) 
         //+ ", fadein_opacite : " + int(fadein_opacite) + ", fadeout_opacite : " + int(fadeout_opacite) 
         + " -- " + "/video/param width : " + int(r_width) + ", height " + int(r_height), 10, 18);
  }
    
  // Afficher les données correspondant à l'objet choisi *****************************
   
  TableRow ligne = objet.getRow(id-1);
  
  fill(255); // Couleur du texte
  
  textFont(police, 18);
  x_start = 690;
  y_start = 100;
  
  String o_date = ligne.getString("jour") + "/" + ligne.getString("mois") + "/" + ligne.getString("annee");
  text("Jour " + ligne.getString("id") + " - " + o_date, x_start, y_start);
  text(ligne.getString("depart") + " >> " + ligne.getString("arrivee"), x_start, y_start + 25);
  
  text(ligne.getString("lieu"), x_start, y_start + 75);
  
  if (!ligne.getString("objet").equals("0")) text(ligne.getString("objet"), x_start, y_start + 100);
  if (!ligne.getString("contexte").equals("0"))text(ligne.getString("contexte"), x_start, y_start + 125);
  
  textFont(police, 14);
  x_start = 690;
  y_start = 260;
  
  text("Poids   : " + ligne.getInt("poids") + " g",   x_start, y_start);
  text("Taille  : " + ligne.getInt("taille") + " mm", x_start, y_start + 20);
  text("Couleur : " + ligne.getString("couleur"),     x_start, y_start + 40);
  text("Matière : " + ligne.getString("matiere"),     x_start, y_start + 60);
  text("Origine : " + ligne.getString("origine"),     x_start, y_start + 80);
  
  x_start = 900;
  y_start = 260;
  
  lat = ligne.getFloat("lat_dec");
  lon = ligne.getFloat("long_dec");
  text("Latitude  : " + lat + "°",                          x_start, y_start);
  text("Longitude : " + lon + "°",                          x_start, y_start + 20);
  text("KMs jour  : " + ligne.getInt("kms") + " km",        x_start, y_start + 40);
  text("KMs total : " + ligne.getInt("kms_cumule") + " km", x_start, y_start + 60);
  text("Altitude  : " + ligne.getInt("alti") + " m",        x_start, y_start + 80);
  
  // Afficher le fond de carte et placer les coordonnées de l'objet *************************
  
  image(planisphere, planisphere_start.x, planisphere_start.y);
  pixel_loc = mm.getScreenLocation( new PVector(lat,lon) ); // conversion WGS84 -> écran
  fill(255);
  stroke(0);
  ellipse(pixel_loc.x + planisphere_start.x, pixel_loc.y + planisphere_start.y, 6, 6);
  
}


// Charger l'image quand un nouvel id est reçu, si jamais le fichier n'existe pas
// une image vide est créée à la place...
void chargerImageObjet(String dir, int id) {
  String chemin = dir + "/J" + id + ".jpg";
  File f = dataFile(chemin);
  if (f.isFile()) {
      image_objet = loadImage(chemin);
    } else {
      println("Le fichier " + chemin + " n'existe pas");
      image_objet = createImage(420, 420, RGB);
    }
}

// Attribution des valeurs aux variables selon les messages OSC reçus 
void oscEvent(OscMessage theOscMessage) {

  if (theOscMessage.checkAddrPattern("/video/shape") == true) {
    r_id      = theOscMessage.get(0).floatValue();
    r_level   = theOscMessage.get(1).floatValue();
    r_fadein  = theOscMessage.get(2).floatValue();
    r_hold    = theOscMessage.get(3).floatValue();
    r_fadeout = theOscMessage.get(4).floatValue();
    nouvelle_reception = true;
    
    if (DEBUG) print(theOscMessage);
    if (DEBUG) println(" : " + r_id + ", " + r_level + ", " + r_fadein + ", " + r_hold + ", " + r_fadeout);
    
    return;
  } 

  if (theOscMessage.checkAddrPattern("/video/param") == true) {
    r_width  = theOscMessage.get(0).floatValue();
    r_height = theOscMessage.get(1).floatValue();
    
    if (DEBUG) print(theOscMessage);
    if (DEBUG) println(" : " + r_id + ", " + r_level + ", " + r_fadein + ", " + r_hold + ", " + r_fadeout);
    
    return;
  }
}



/**
 * Utility class to convert between geo-locations and Cartesian screen coordinates.
 * Can be used with a bounding box defining the map section.
 *
 * (c) 2011 Till Nagel, tillnagel.com
 */
public class MercatorMap {
  
  public static final float DEFAULT_TOP_LATITUDE = 80;
  public static final float DEFAULT_BOTTOM_LATITUDE = -80;
  public static final float DEFAULT_LEFT_LONGITUDE = -180;
  public static final float DEFAULT_RIGHT_LONGITUDE = 180;
  
  /** Horizontal dimension of this map, in pixels. */
  protected float mapScreenWidth;
  /** Vertical dimension of this map, in pixels. */
  protected float mapScreenHeight;

  /** Northern border of this map, in degrees. */
  protected float topLatitude;
  /** Southern border of this map, in degrees. */
  protected float bottomLatitude;
  /** Western border of this map, in degrees. */
  protected float leftLongitude;
  /** Eastern border of this map, in degrees. */
  protected float rightLongitude;

  private float topLatitudeRelative;
  private float bottomLatitudeRelative;
  private float leftLongitudeRadians;
  private float rightLongitudeRadians;

  public MercatorMap(float mapScreenWidth, float mapScreenHeight) {
    this(mapScreenWidth, mapScreenHeight, DEFAULT_TOP_LATITUDE, DEFAULT_BOTTOM_LATITUDE, DEFAULT_LEFT_LONGITUDE, DEFAULT_RIGHT_LONGITUDE);
  }
  
  /**
   * Creates a new MercatorMap with dimensions and bounding box to convert between geo-locations and screen coordinates.
   *
   * @param mapScreenWidth Horizontal dimension of this map, in pixels.
   * @param mapScreenHeight Vertical dimension of this map, in pixels.
   * @param topLatitude Northern border of this map, in degrees.
   * @param bottomLatitude Southern border of this map, in degrees.
   * @param leftLongitude Western border of this map, in degrees.
   * @param rightLongitude Eastern border of this map, in degrees.
   */
  public MercatorMap(float mapScreenWidth, float mapScreenHeight, float topLatitude, float bottomLatitude, float leftLongitude, float rightLongitude) {
    this.mapScreenWidth = mapScreenWidth;
    this.mapScreenHeight = mapScreenHeight;
    this.topLatitude = topLatitude;
    this.bottomLatitude = bottomLatitude;
    this.leftLongitude = leftLongitude;
    this.rightLongitude = rightLongitude;
    this.topLatitudeRelative = getScreenYRelative(topLatitude);
    this.bottomLatitudeRelative = getScreenYRelative(bottomLatitude);
    this.leftLongitudeRadians = getRadians(leftLongitude);
    this.rightLongitudeRadians = getRadians(rightLongitude);
  }

  /**
   * Projects the geo location to Cartesian coordinates, using the Mercator projection.
   *
   * @param geoLocation Geo location with (latitude, longitude) in degrees.
   * @returns The screen coordinates with (x, y).
   */
  public PVector getScreenLocation(PVector geoLocation) {
    float latitudeInDegrees = geoLocation.x;
    float longitudeInDegrees = geoLocation.y;
    return new PVector(getScreenX(longitudeInDegrees), getScreenY(latitudeInDegrees));
  }
  
  private float getScreenYRelative(float latitudeInDegrees) {
    return log(tan(latitudeInDegrees / 360f * PI + PI / 4));
  }

  protected float getScreenY(float latitudeInDegrees) {
    return mapScreenHeight * (getScreenYRelative(latitudeInDegrees) - topLatitudeRelative) / (bottomLatitudeRelative - topLatitudeRelative);
  }
  
  private float getRadians(float deg) {
    return deg * PI / 180;
  }

  protected float getScreenX(float longitudeInDegrees) {
    float longitudeInRadians = getRadians(longitudeInDegrees);
    return mapScreenWidth * (longitudeInRadians - leftLongitudeRadians) / (rightLongitudeRadians - leftLongitudeRadians);
  }
}

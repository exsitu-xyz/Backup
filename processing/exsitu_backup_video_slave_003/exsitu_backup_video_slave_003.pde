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
PImage pointeur;

// Divers assets ***********************************************
PFont police1;
PFont police2;
PFont police3;
int x_start, y_start; // variables utilisés pour l'affichage des données

// Variables utilisées pour l'animation ************************
int old_id = -1;
float fps = 30;            // Frames par secondes, mis à jour dynamiquement ci-dessous
float objet_start;         // en millisecondes, moment d'apparition de l'objet
float opacite_cache = 255; // valeur d'opacité du cache noir utilisé pour les fondus

// Add more evolve fadein/fadeout for multiple objects (max 8 right now with a maximum opacity of 50% [0.5])
float MAX_OPACITY_EACH_IMAGE = 1.0;
int MAX_IMAGES_SAME_TIME = 8;

class DisplayedImage {
  PImage image_objet;
  int initTimerMs = 0;
  
  // Fade in parameter (duration, initial time of the fadein and end timer of the fadein)
  int fadeinDurationMs = 0;
  int fadeinBeginTimer = 0;
  int fadeinEndTimer = 0;
  // Same for hold
  int holdDurationMs = 0;
  int holdBeginTimer = 0;
  int holdEndTimer = 0;
  // Same for fadeout
  int fadeoutDurationMs = 0;
  int fadeoutBeginTimer = 0;
  int fadeoutEndTimer = 0;
  
  float maximumIntensity = 1.0;
  
  int currentIntervalDurationMs = 0;
  
  DisplayedImage(int id, float fadeinDurationMs, float holdDurationMs, float fadeoutDurationMs, float maximumIntensity) {
    this.initTimerMs = millis();
    this.maximumIntensity = maximumIntensity / 255.0; // Intensity is between 0 to 255
    
    this.fadeinDurationMs = (int)fadeinDurationMs;
    this.holdDurationMs = (int)holdDurationMs;
    this.fadeoutDurationMs = (int)fadeoutDurationMs;
    
    this.fadeinBeginTimer = this.initTimerMs;
    this.fadeinEndTimer = this.initTimerMs + this.fadeinDurationMs;
    
    this.holdBeginTimer = this.fadeinEndTimer;
    this.holdEndTimer = this.holdBeginTimer + this.holdDurationMs;
    
    this.fadeoutBeginTimer = this.holdEndTimer;
    this.fadeoutEndTimer = this.fadeoutBeginTimer + this.fadeinDurationMs;
    
    
    this.chargerImageObjet(dossier_images, id);
  }
  
  float getInitialCreation() {
   return this.initTimerMs; 
  }
  
  PImage getImage() {
     return this.image_objet; 
  }
  
  boolean isFinish() {
   return millis() > (initTimerMs + fadeinDurationMs + holdDurationMs + fadeoutDurationMs);
  }
  
  float getCurrentAlpha() {
    // Compute a value between 0 (transparent) to 1 (opaque)
    int currentTimer = millis();
    // By default no opacity (before and after)
    float currentOpacity = 0.0;
    // Hold period (full opacity)
    if (currentTimer >= this.holdBeginTimer && currentTimer <= this.holdEndTimer) {
      currentOpacity = 1.0;
    // Fadein period
    } else if (currentTimer >= this.fadeinBeginTimer && currentTimer <= this.fadeinEndTimer) {
      float t_init = 0;
      float t_current = currentTimer - this.fadeinBeginTimer;
      float t_end = this.fadeinEndTimer - this.fadeinBeginTimer;
      currentOpacity = t_current / t_end;
    // Fadeout period
    } else if (currentTimer >= this.fadeoutBeginTimer && currentTimer <= this.fadeoutEndTimer) {
      float t_init = 0;
      float t_current = currentTimer - this.fadeoutBeginTimer;
      float t_end = this.fadeoutEndTimer - this.fadeoutBeginTimer;
      currentOpacity = 1.0 - (t_current / t_end);
    }
    return currentOpacity * 255 * this.maximumIntensity * MAX_OPACITY_EACH_IMAGE;
  }
  
  // Charger l'image quand un nouvel id est reçu, si jamais le fichier n'existe pas
  // une image vide est créée à la place...
  void chargerImageObjet(String dir, int id) {
    String chemin = dir + "/J" + id + ".jpg";
    File f = dataFile(chemin);
    if (f.isFile()) {
        this.image_objet = loadImage(chemin);
      } else {
        println("Le fichier " + chemin + " n'existe pas");
        this.image_objet = createImage(420, 420, RGB);
      }
  }
}

class AllDisplayedImages {
   DisplayedImage[] allImages = new DisplayedImage[MAX_IMAGES_SAME_TIME];
  
  void addImage(int id, float fadeinDurationMs, float holdDurationMs, float fadeoutDurationMs, float maximumIntensity) {
     int usedIndex = this.getEmptyIndex();
     this.allImages[usedIndex] = new DisplayedImage(id, fadeinDurationMs, holdDurationMs, fadeoutDurationMs, maximumIntensity);
    println( "Add image on index: " +usedIndex + " for image with the ID : " + id + ". Number of image: " + allImages.length + "    initTimer : " + allImages[usedIndex].getInitialCreation() );
    println( "Is finish ? " + this.allImages[usedIndex].isFinish());
  }
  
  int getEmptyIndex() {
    for (int currentIndex = 0; currentIndex < this.allImages.length; currentIndex++) {
       if(this.allImages[currentIndex] == null) {
         return currentIndex;
       }
    }
    return this.getOldestImage();
  }
  
  int getOldestImage() {
    float minimumTimer = millis() + 365*24*3600*10;
    int index = 0;
    for (int currentIndex = 0; currentIndex < this.allImages.length; currentIndex++) {
      DisplayedImage image = this.allImages[currentIndex];
      if (image.getInitialCreation() <= minimumTimer) {
        minimumTimer = image.getInitialCreation();
        index = currentIndex;
      }
    }
    return index;
  }
  
  void displayImages() {
    int nbImage = 0;
    String debugAlpha = "";
    for (int currentIndex = 0; currentIndex < this.allImages.length; currentIndex++) {
      DisplayedImage ci = this.allImages[currentIndex];
      if (ci == null) {
        // Nothing to do with an empty image
      } else if (ci.isFinish() ) {
        // If the image is finished we detroyed this image
        allImages[currentIndex] = null;
      } else {
        debugAlpha += "index[" + currentIndex + "] = " + ci.getCurrentAlpha();
        // Display image in other case
        tint(255, 255, 255, ci.getCurrentAlpha());
        image(ci.getImage(), 170, 50, 400, 400); 
         nbImage++;
      }
    }
    println( "Nb current images display: " + nbImage + " with " + debugAlpha);
  }
  
}

AllDisplayedImages imagesManager = null;

void setup() {
  size(1280, 800, P3D);
  noCursor(); // Pour éviter qu'un curseur de souris se ballade ...
  frameRate(30);
  
  // Mettre en place la communication OSC
  oscP5 = new OscP5(this, 8003); // écoute des messages OSC sur le port 8003
  myRemoteLocation = new NetAddress("127.0.0.1", 12000);

  // Mettre en place le gestionnaire d'images
  imagesManager = new AllDisplayedImages();
  // Charger une image
  imagesManager.addImage(int(r_id), 1.0, 2.0, 1.0, 1.0);
  
  // Charger la police 
  police1 = loadFont("Gunplay-Regular-48.vlw");
  police2 = loadFont("TlwgMono-Bold-48.vlw");
  police3 = loadFont("TlwgMono-48.vlw");
  
  // Charger le fond de carte
  planisphere = loadImage("mercator_540x288.jpg"); 
  planisphere_start = new PVector(100, 450);
  
  // Charger le pointeur de carte
  pointeur = loadImage("dot.png");

  // définir l'objet de conversion coord. géoloc -> pixels
  mm = new MercatorMap(540, 288, 75, -60, -168, 192);
    
  // Charger la base de données des objets
  objet = loadTable("data/" + base_objets, "header");
  if (DEBUG) println(objet.getRowCount() + " lignes dans la base");
  
  background(0);

}


void draw() {
  
  // Quel est le framerate réel ? On l'utilisera pour le calcul des fondus
  fps = frameRate;
  
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
    
    // New way to display image
    imagesManager.addImage(id, r_fadein, r_hold, r_fadeout, r_level);
    
    nouvelle_reception = false;
  }
  
  // Afficher l'image de l'objet ************************************************************

  imagesManager.displayImages();
  
  // Afficher le fond de carte et placer les coordonnées de l'objet *************************
  
  image(planisphere, planisphere_start.x, planisphere_start.y);
  pixel_loc = mm.getScreenLocation( new PVector(lat,lon) ); // conversion WGS84 -> écran
  blendMode(ADD);
  image(pointeur, pixel_loc.x + planisphere_start.x - 50, pixel_loc.y + planisphere_start.y - 50, 100, 100);
  blendMode(BLEND);
  
  // Recouvrir le texte de noir à chaque frame **********************************************
  noStroke();
  fill(0);
  rect(690, 0, 550, 800);
    
  // Afficher les données correspondant à l'objet choisi ************************************
   
  TableRow ligne = objet.getRow(id-1);
  
  x_start = 740;
  y_start = 120;

  fill(180); // Couleur du texte

  textFont(police1, 24);
  text("Jour " + ligne.getString("id"),                                                               x_start, y_start);

  fill(255); // Couleur du texte

  textFont(police2, 18);
  text(ligne.getString("date_full"),                                                                  x_start, y_start + 35);
  text(ligne.getString("pays"),                                                                       x_start, y_start + 65);
  
  textFont(police2, 16);
  text(ligne.getString("lieu"),                                                                       x_start, y_start + 90);

  textFont(police3, 14);
  text(" | " + ligne.getString("gps"),                                                                x_start + 110, y_start + 65);
  if (!ligne.getString("contexte").equals("0"))text(ligne.getString("contexte"),                      x_start, y_start + 110);
    
  y_start = 280;

  textFont(police2, 20);
  if (!ligne.getString("objet").equals("0")) text(ligne.getString("objet"),                           x_start, y_start);

  textFont(police3, 14);
  text("Poids   : ",                                                                                  x_start, y_start + 25);
  text("Taille  : ",                                                                                  x_start, y_start + 40);
  text("Couleur : ",                                                                                  x_start, y_start + 55);
  text("Matière : ",                                                                                  x_start, y_start + 70);
  text("Origine : ",                                                                                  x_start, y_start + 85);
  
  textFont(police2, 14);
  text(ligne.getString("poids") + " g",                                                                  x_start + 100, y_start + 25);
  text(ligne.getString("taille") + " mm",                                                                x_start + 100, y_start + 40);
  text(ligne.getString("couleur"),                                                                    x_start + 100, y_start + 55);
  text(ligne.getString("matiere"),                                                                    x_start + 100, y_start + 70);
  text(ligne.getString("origine"),                                                                    x_start + 100, y_start + 85);
  
  y_start = 420;
  
  textFont(police3, 14);
  text("Altitude  : ",                                                                                x_start, y_start);
  text("Latitude  : ",                                                                                x_start, y_start + 20);
  text("Longitude : ",                                                                                x_start, y_start + 40);

  textFont(police2, 14);
  text(ligne.getInt("alti") + " m",                                                                   x_start + 100, y_start);
  lat = ligne.getFloat("lat_dec");
  lon = ligne.getFloat("long_dec");
  text(lat + "°",                                                                                     x_start + 100, y_start + 20);
  text(lon + "°",                                                                                     x_start + 100, y_start + 40);

  y_start = 500;
  
  textFont(police3, 14);
  text("KMs jour  : ",                                                                                x_start, y_start + 20);
  text("KMs total : ",                                                                                x_start, y_start + 40);

  textFont(police2, 14);
  text(ligne.getString("depart") + " >> " + ligne.getString("arrivee"),                               x_start, y_start);
  text(ligne.getInt("kms") + " km",                                                                   x_start + 100, y_start + 20);
  text(ligne.getInt("kms_cumule") + " km",                                                            x_start + 100, y_start + 40);

  y_start = 600;
  
  fill(164); // Couleur du texte

  textFont(police3, 12);
  
  text("Segment d'étape  : " + ligne.getInt("kms_etape_segments") + " km",                         x_start, y_start);
  text("Segments cumulés : " + ligne.getInt("kms_etape_cumule") + " km",                           x_start, y_start + 15);
  
  text("Distance du départ (vol d'oiseau) : " + ligne.getInt("kms_depart_vol_oiseau") + " km",     x_start, y_start + 45);
  text("Distance du départ (corde)        : " + ligne.getInt("kms_depart_corde") + " km",          x_start, y_start + 60);

  text("Latitude  : " + ligne.getString("lat_rad") + " rad",                                          x_start, y_start + 90);
  text("| " + ligne.getString("lat_dec"),                                                             x_start + 280, y_start + 90);
  text("Longitude : " + ligne.getString("long_rad") + " rad",                                         x_start, y_start + 105);
  text("| " + ligne.getString("long_dec"),                                                            x_start + 280, y_start + 105);
  
  if (DEBUG) { // DEBUG : Affichage écran des étapes de fondu *********************************
    textFont(police3, 12);
    fill(0);
    rect(0, height - 20, width, 20);
    fill(150);
  }
  
  if (DEBUG) { // DEBUG : Affichage des valeurs reçues par OSC ********************************
    fill(0);
    rect(0, 0, width, 40);
    fill(150);
    noStroke();
    textFont(police3, 12);
    text("DEBUG : fps : " + int(frameRate) + " -- /video/shape id : " + int(r_id) + ", level : " + r_level 
         + ", fadein : " + int(r_fadein) + ", hold : " + int(r_hold) + ", fadeout : " + int(r_fadeout) 
         //+ ", fadein_opacite : " + int(fadein_opacite) + ", fadeout_opacite : " + int(fadeout_opacite) 
         + " -- " + "/video/param width : " + int(r_width) + ", height " + int(r_height), 10, 18);
  }
  
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
      image_objet = createImage(640, 640, RGB);
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

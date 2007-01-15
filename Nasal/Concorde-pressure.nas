# EXPORT : functions ending by export are called from xml
# CRON : functions ending by cron are called from timer
# SCHEDULE : functions ending by schedule are called from cron



# ==============
# PRESSURIZATION
# ==============

Pressurization = {};

Pressurization.new = func {
   obj = { parents : [Pressurization],

           diffpressure : Differentialpressure.new(),

           engines : nil,
           internal : nil,
           pressurenode : nil,
           valves : nil,
           systems : nil,

           PRESSURIZESEC : 5.0,                       # sampling

           speedup : 1.0,

           DEPRESSURIZEINHGPM : 10.0,                 # 10 inhg/minute (guess)
           LEAKINHGPM : 0.01,                         # 0.01 inhg/minute if no pressurization

           PRESSURIZEINHGPM : 0.0,                    # 18 mbar/minute = 0.53 inhg/minute

           MININHG : 19.82,                           # 11000 ft

           DEPRESSURIZEINHG : 0.0,
           LEAKINHG : 0.0,
           PRESSURIZEINHG : 0.0,
           PRESSURIZEMININHG : 0.0,

           cabininhg : constant.P0_inhg,
           datuminhg : constant.P0_inhg,
           outflowinhg : 0.0,
           pressureinhg : constant.P0_inhg,
           targetinhg : constant.P0_inhg,

           THRUSTPSI : 7.0,
           THRUSTOFFPSI : 3.0,
           GROUNDPSI : 1.45,

           diffpsi : 0.0,

           LANDINGFT : 2500.0,

           PRESSURIZEFT : 0.0,                        # max descent speed around 6000 feet/minute.

           altseaft : 0.0,

           PRESSURIZEMAXFTPM : 7000.0,
           CLIMBFTPM : 2000.0,
           DESCENTFTPM : 1500.0,

           ground : constant.TRUE,
           system_no : 0,

           staticport : "",
           slave : { "air" : nil, "electric" : nil, "weight": nil }
         };

   obj.init();

   return obj;
};

Pressurization.init = func {
    propname = getprop("/systems/pressurization/slave/air");
    me.slave["air"] = props.globals.getNode(propname);
    propname = getprop("/systems/pressurization/slave/electric");
    me.slave["electric"] = props.globals.getNode(propname);
    propname = getprop("/systems/pressurization/slave/weight");
    me.slave["weight"] = props.globals.getNode(propname);

    me.LEAKINHG = me.LEAKINHGPM / ( constant.MINUTETOSECOND / me.PRESSURIZESEC );
    me.DEPRESSURIZEINHG = me.DEPRESSURIZEINHGPM / ( constant.MINUTETOSECOND / me.PRESSURIZESEC );

    me.PRESSURIZEFT = me.PRESSURIZEMAXFTPM / ( constant.MINUTETOSECOND / me.PRESSURIZESEC );

    me.engines = props.globals.getNode("/controls/engines").getChildren("engine");
    me.internal = props.globals.getNode("/systems/pressurization/internal");
    me.pressurenode = props.globals.getNode("/systems/pressurization");
    me.valves = props.globals.getNode("/systems/pressurization/valve");
    me.systems = props.globals.getNode("/systems/pressurization").getChildren("system");

    me.staticport = getprop("/systems/pressurization/static-pressure");

    me.initconstant();

    me.diffpressure.set_rate( me.PRESSURIZESEC );
}

# engineer can change
Pressurization.initconstant = func {
    pressurizembarpm = me.systems[me.system_no].getChild("mbar-per-min").getValue();

    me.PRESSURIZEINHGPM = pressurizembarpm * constant.MBARTOINHG;
    me.PRESSURIZEINHG = me.PRESSURIZEINHGPM / ( constant.MINUTETOSECOND / me.PRESSURIZESEC );

    me.datuminhg = me.systems[me.system_no].getChild("datum-mbar").getValue() * constant.MBARTOINHG;
    altitudeft = me.systems[me.system_no].getChild("cabin-alt-ft").getValue();
    me.PRESSURIZEMININHG = constant.pressure_inhg( altitudeft );

    stepinhg = me.datuminhg - me.PRESSURIZEMININHG;
    maxdiffft = ( stepinhg / me.PRESSURIZEINHGPM ) * me.CLIMBFTPM;
    me.systems[me.system_no].getChild("max-diff-ft").setValue(maxdiffft);

    me.speedup = getprop("/sim/speed-up");
    if( me.speedup > 1 ) {
        me.PRESSURIZEINHG = me.PRESSURIZEINHG * me.speedup;
    }

   
    me.systems[me.system_no].getChild("min-pressure-inhg").setValue(me.PRESSURIZEMININHG);
}

Pressurization.ground_relief = func {
    me.pressureinhg = getprop(me.staticport);
    me.cabininhg = me.pressurenode.getChild("pressure-inhg").getValue();
    
    me.diffpsi = ( me.cabininhg - me.pressureinhg ) * constant.INHGTOPSI;

    # opens ground relief valve if not takeoff
    me.ground = constant.FALSE;
    if( me.slave["weight"].getChild("wow").getValue() and
        me.engines[0].getChild("throttle" ).getValue() < 1.0 and
        me.engines[1].getChild("throttle" ).getValue() < 1.0 and
        me.engines[2].getChild("throttle" ).getValue() < 1.0 and
        me.engines[3].getChild("throttle" ).getValue() < 1.0 ) {
        if( me.valves.getChild("ground-auto").getValue() ) {
            if( me.diffpsi < me.GROUNDPSI ) {
                me.ground = constant.TRUE;
            }
        }
    }

    me.valves.getChild("ground-relief").setValue(me.ground);
}

Pressurization.thrust_recuperator = func {
    if( me.diffpsi < me.THRUSTOFFPSI ) {
        thrust = constant.FALSE;
        recuperator = constant.FALSE;
    }
    elsif( me.diffpsi < me.THRUSTPSI ) {
        thrust = constant.FALSE;
        recuperator = constant.TRUE;
    }
    else {
        thrust = constant.TRUE;
        recuperator = constant.TRUE;
    }

    me.valves.getChild("thrust").setValue(thrust);
    me.valves.getChild("thrust-recuperator").setValue(recuperator);
}

Pressurization.flow = func( maxinhg, mininhg ) {
    me.pressureinhg = getprop(me.staticport);
    me.altseaft = constant.altitude_ft( me.pressureinhg, me.datuminhg );
    me.targetinhg = me.pressureinhg;
    me.cabininhg = me.pressurenode.getChild("pressure-inhg").getValue();
    result = me.cabininhg;

    if( me.targetinhg < mininhg ) {
        me.targetinhg = mininhg;
    }

    me.outflowinhg = me.cabininhg - me.targetinhg;
    if( me.outflowinhg > maxinhg ) {
        me.outflowinhg = maxinhg;
    }
    elsif( me.outflowinhg < -maxinhg ) {
        me.outflowinhg = -maxinhg;
    }

    me.cabininhg = me.cabininhg - me.outflowinhg;

    me.apply( constant.TRUE );
}

Pressurization.depressurization = func {
    maxinhg = me.DEPRESSURIZEINHG * me.speedup;

    # limited to 11000 ft
    me.flow( maxinhg, me.MININHG );
}

# leak when no pressurization
Pressurization.cabinleak = func {
    maxinhg = me.LEAKINHG * me.speedup;

    me.flow( maxinhg, 0.0 );
}

Pressurization.last = func {
    me.pressureinhg = getprop(me.staticport);
    me.altseaft = constant.altitude_ft( me.pressureinhg, me.datuminhg );
    me.cabininhg = me.pressurenode.getChild("pressure-inhg").getValue();


    # filters startup
    if( me.altseaft == nil or me.pressureinhg == nil ) {
        me.altseaft = 0.0;
        me.pressureinhg = constant.P0_inhg;

        me.targetinhg = constant.P0_inhg;
        me.outflowinhg = 0.0;

        startup = constant.TRUE;
     }
     else {
        startup = constant.FALSE;
     }

     return startup;
}

# pressurization curve has a lower slope than aircraft descent/climb profile
Pressurization.curve = func {
     # average vertical speed of 2000 feet/minute
     if( me.altseaft > me.LANDINGFT ) {
         minutes = me.altseaft / me.CLIMBFTPM;
         minutes = minutes * me.speedup;
         me.targetinhg = me.datuminhg - minutes * me.PRESSURIZEINHGPM;
         if( me.targetinhg < me.PRESSURIZEMININHG ) {
             me.targetinhg = me.PRESSURIZEMININHG;
         }
     }

     # average landing speed of 1500 feet/minute
     else {
         minutes = me.altseaft / me.DESCENTFTPM;
         minutes = minutes * me.speedup;
         me.targetinhg = me.datuminhg - minutes * me.PRESSURIZEINHGPM;
         if( me.targetinhg < me.PRESSURIZEMININHG ) {
             me.targetinhg = me.PRESSURIZEMININHG;
         }
     }
}

Pressurization.real = func {
      me.outflowinhg = me.targetinhg - me.cabininhg;
      if( me.cabininhg < me.targetinhg ) {
          if( me.outflowinhg > me.PRESSURIZEINHG ) {
              me.outflowinhg = me.PRESSURIZEINHG;
          }
          me.cabininhg = me.cabininhg + me.outflowinhg;
      }
      elsif( me.cabininhg > me.targetinhg ) {
          if( me.outflowinhg < -me.PRESSURIZEINHG ) {
              me.outflowinhg = -me.PRESSURIZEINHG;
          }
          me.cabininhg = me.cabininhg + me.outflowinhg;
      }
      # balance
      else {
          me.outflowinhg = 0;
          me.cabininhg = me.targetinhg;
      }
}

Pressurization.interpolation = func {
      # one supposes instrument calibrated by standard atmosphere
      if( me.outflowinhg != 0 or me.cabininhg > me.PRESSURIZEMININHG ) {
          interpol = constant.TRUE;
      }

      # above 8000 ft
      else {
          interpol = constant.FALSE;
      }

      return interpol;
}

# relocation in flight
Pressurization.relocation = func( interpol ) {
      lastaltft = me.internal.getChild("altitude-sea-ft").getValue();

      variationftpm = lastaltft - me.altseaft;
      if( variationftpm < -me.PRESSURIZEFT or variationftpm > me.PRESSURIZEFT ) {
           me.outflowinhg = 0.0;
           me.cabininhg = me.targetinhg;
           interpol = constant.TRUE;        
      }
      # relocation on ground (change of airport)
      elsif( me.ground ) {
           me.outflowinhg = 0.0;
           me.targetinhg = me.pressureinhg;
           me.cabininhg = me.targetinhg;
           interpol = constant.TRUE;
      }

      return interpol;
}

Pressurization.apply = func( interpol ) {
      me.internal.getChild("atmosphere-inhg").setValue(me.pressureinhg);
      me.internal.getChild("target-inhg").setValue(me.targetinhg);
      me.internal.getChild("outflow-inhg").setValue(me.outflowinhg);
      me.internal.getChild("altitude-sea-ft").setValue(me.altseaft);

      if( !interpol ) {
          me.cabininhg = me.PRESSURIZEMININHG;
      }

      result = me.pressurenode.getChild("pressure-inhg").getValue();
      if( result != me.cabininhg ) {
          interpolate("/systems/pressurization/pressure-inhg",me.cabininhg,me.PRESSURIZESEC);
      }
}

Pressurization.system = func {
   startup = me.last();

   # real modes
   if( !startup ) {
       me.curve();
       me.real();
   }

   interpol = me.interpolation();

   # artificial modes
   if( !startup ) {
       interpol = me.relocation( interpol );
   }

   me.apply( interpol );
}

Pressurization.schedule = func {
   if( me.slave["electric"].getChild("specific").getValue() ) {
       if( me.pressurenode.getChild("serviceable").getValue() ) {
           me.initconstant();
           me.ground_relief();

           if( getprop("/controls/pressurization/emergency/depressurization") ) {
               me.depressurization();
           }

           elsif( me.slave["air"].getChild("pressurization").getValue() ) {
               me.system();
           }

           # leaks
           else {
               me.cabinleak();
           }

           me.thrust_recuperator();
       }
   }


   # energy provided by differential pressure
   me.diffpressure.schedule();
}


# =====================
# DIFFERENTIAL PRESSURE
# =====================

Differentialpressure = {};

Differentialpressure.new = func {
   obj = { parents : [Differentialpressure],

           DIFFSEC : 5.0,

           staticport : ""                         # energy provided by differential pressure
         };

   obj.init();

   return obj;
};

Differentialpressure.init = func {
    me.staticport = getprop("/instrumentation/differential-pressure/static-pressure");
}

Differentialpressure.set_rate = func( rates ) {
    me.DIFFSEC = rates;
}

Differentialpressure.schedule = func {
   cabininhg = getprop("/systems/pressurization/pressure-inhg");
   pressureinhg = getprop(me.staticport);
   diffpsi = ( cabininhg - pressureinhg ) * constant.INHGTOPSI;

   result = getprop("/instrumentation/differential-pressure/differential-psi");
   if( result != diffpsi ) {
       interpolate("/instrumentation/differential-pressure/differential-psi",diffpsi,me.DIFFSEC);
   }
}


# =========
# AIR BLEED
# =========

Airbleed = {};

Airbleed.new = func {
   obj = { parents : [Airbleed],

           airconditioning : Airconditioning.new(),

           AIRSEC : 1.0,                              # refresh rate

           MAXPSI : 65.0,                             # maximum pressure
           GROUNDPSI : 35.0,                          # ground supply pressure
           NOPSI : 0.0,

           valves : nil,
           bleeds : nil,
           airbleed : nil,

           adjacent : { 0 : 1, 1 : 0, 2 : 3, 3 : 2  },

           noinstrument : { "agl" : "", "airspeed" : "" },
           slave : { "engine" : nil, "gear" : nil }
         };

   obj.init();

   return obj;
};

Airbleed.init = func {
    me.noinstrument["agl"] = getprop("/systems/air-bleed/noinstrument/agl");
    me.noinstrument["airspeed"] = getprop("/systems/air-bleed/noinstrument/airspeed");

    propname = getprop("/systems/air-bleed/slave/engine");
    me.slave["engine"] = props.globals.getNode(propname).getChildren("engine");
    propname = getprop("/systems/air-bleed/slave/gear");
    me.slave["gear"] = props.globals.getNode(propname);

    me.valves = props.globals.getNode("/controls/pneumatic/").getChildren("engine");
    me.bleeds = props.globals.getNode("/systems/air-bleed/").getChildren("engine");
    me.airbleed = props.globals.getNode("/systems/air-bleed/");
}

Airbleed.set_rate = func( rates ) {
    me.AIRSEC = rates;

    me.airconditioning.set_rate( me.AIRSEC );
}

Airbleed.slowschedule = func {
    me.door();

    me.airconditioning.slowschedule();
}

# detects loss of all engines
Airbleed.schedule = func {
   serviceable = me.airbleed.getChild("serviceable").getValue();

   # ground supply
   groundpsi = me.airbleed.getNode("ground-service").getChild("pressure-psi").getValue();

   # ===============================
   # bleed valve limits the pressure
   # ===============================
   for( i = 0; i < 4; i = i+1 ) {
        if( serviceable and
            me.slave["engine"][i].getChild("running").getValue() and
            me.valves[i].getChild("bleed-valve").getValue() ) {
            # maximum 65 PSI
            pressurepsi = me.MAXPSI;
        }
        else {
            pressurepsi = me.NOPSI;
        }

        result = me.bleeds[i].getChild("bleed-psi").getValue();
        me.apply("/systems/air-bleed/engine[" ~ i ~ "]/bleed-psi",pressurepsi,result);

        # ===========
        # cross bleed
        # ===========
        bleedpsi = pressurepsi;
        if( me.valves[i].getChild("cross-bleed-valve").getValue() and bleedpsi == 0.0 ) {
            pressurepsi = 0.0;
            # adjacent engine
            a = me.adjacent[i];
            if( me.valves[a].getChild("cross-bleed-valve").getValue() ) {
                pressurepsi = me.bleeds[a].getChild("bleed-psi").getValue();
            }
            # ground supply
            if( pressurepsi == me.NOPSI ) {
                pressurepsi = groundpsi;
            }
        }
        else {
            pressurepsi = bleedpsi;
        }

        result = me.bleeds[i].getChild("cross-psi").getValue();
        me.apply("/systems/air-bleed/engine[" ~ i ~ "]/cross-psi",pressurepsi,result);

        # ==================
        # conditioning valve
        # ==================
        crosspsi = pressurepsi;
        if( me.valves[i].getChild("conditioning-valve").getValue() ) {
            pressurepsi = crosspsi;
        }
        else {
            pressurepsi = me.NOPSI;
        }

        result = me.bleeds[i].getChild("conditioning-psi").getValue();
        me.apply("/systems/air-bleed/engine[" ~ i ~ "]/conditioning-psi",pressurepsi,result);
   }

   # jet pump only when landing gear down
   if( me.slave["gear"].getChild("position-norm").getValue() == 1.0 ) {
       for( i = 0; i < 4; i = i+1 ) {
            me.bleeds[i].getChild("jet-pump").setValue(constant.TRUE);
       }
   }
   else {
       for( i = 0; i < 4; i = i+1 ) {
            me.bleeds[i].getChild("jet-pump").setValue(constant.FALSE);
       }
   }

   # pressurization doesn't see the 4 distinct groups : will get the result after the interpolate
   pressurization = constant.FALSE;
   for( i = 0; i < 4; i = i+1 ) {
        condpsi = me.bleeds[i].getChild("conditioning-psi").getValue();
        if( condpsi >= me.MAXPSI ) {
            pressurization = constant.TRUE;
            break;
        }
   }
   me.airbleed.getChild("pressurization").setValue(pressurization);

   me.airconditioning.schedule();
}

Airbleed.apply = func( path, value, result ) {
    if( result != value ) {
        interpolate(path,value,me.AIRSEC);
    }
}

# connection with delay by ground operator
Airbleed.door = func {
    aglft = getprop(me.noinstrument["agl"]);
    speedkt = getprop(me.noinstrument["airspeed"]);
    if( aglft >=  15 or speedkt >= 15 ) {

        # door stays open, has forgotten to call for disconnection !
        me.airbleed.getNode("ground-service").getChild("pressure-psi").setValue(me.NOPSI);
    }
}

Airbleed.groundserviceexport = func {
    aglft = getprop(me.noinstrument["agl"]);
    speedkt = getprop(me.noinstrument["airspeed"]);

    if( aglft <  15 and speedkt < 15 ) {
        supply = me.airbleed.getNode("ground-service").getChild("door").getValue();

        if( supply ) {
            pressurepsi = me.NOPSI;
        }
        else {
            pressurepsi = me.GROUNDPSI;
        }

        me.airbleed.getNode("ground-service").getChild("door").setValue(!supply);
        me.airbleed.getNode("ground-service").getChild("pressure-psi").setValue(pressurepsi);
    }
}

Airbleed.reargroundserviceexport = func {
    me.airconditioning.groundservice();
}


# =================
# AIR CONDITIONNING
# =================

Airconditioning = {};

Airconditioning.new = func {
   obj = { parents : [Airconditioning],

           AIR60SEC : 60.0,                           # warming rate
           VALVESEC : 5.0,
           AIRSEC : 1.0,                              # refresh rate

           speedup : 1.0,

           MINPSI : 65.0,                             # minimum pressure for air conditioning
           NOPSI : 0.0,

           NORMALKGPH : 4200.0,
           NOMASSKGPH : 0.0,

           VALVEH : 1.0,                              # opened : hot air maximum
           VALVEC : 0.0,                              # shut : cold air only

           temperature_valve : 0.0,
           ground_supply : constant.FALSE,

           PRIMARYDEGC : 150.0,
           DUCTDEGC : 30.0,                           # selector range
           DUCTMINDEGC : 5.0,

           ramairdegc : 0.0,

           WARMINGDEGCPMIN : 0.5,                     # cabin
           COOLINGDEGCPMIN : 0.1,                     # isolation

           valves : nil,
           bleeds : nil,
           groups : nil,
           conditioning : nil,

           thegroup : { "1" : 0, "2" : 1, "3" : 2, "4" : 3 },
           thetemperature : { "1" : "flight-deck-degc", "2" : "cabin-fwd-degc", "3" : "cabin-rear-degc",
                              "4" : "cabin-rear-degc" },

           noinstrument : { "agl" : "", "airspeed" : "", "temperature" : "" }
         };

   obj.init();

   return obj;
};

Airconditioning.init = func {
    me.noinstrument["agl"] = getprop("/systems/air-bleed/noinstrument/agl");
    me.noinstrument["airspeed"] = getprop("/systems/air-bleed/noinstrument/airspeed");
    me.noinstrument["temperature"] = getprop("/systems/temperature/noinstrument/temperature");

    me.valves = props.globals.getNode("/controls/temperature/").getChildren("group");
    me.bleeds = props.globals.getNode("/systems/air-bleed/").getChildren("engine");
    me.groups = props.globals.getNode("/systems/temperature/").getChildren("group");
    me.conditioning = props.globals.getNode("/systems/temperature/");
}

Airconditioning.set_rate = func( rates ) {
    me.AIRSEC = rates;
}

Airconditioning.slowschedule = func {
   me.door();
   me.ground_supply = me.conditioning.getNode("ground-service").getChild("door").getValue();

   me.ramairdegc = getprop(me.noinstrument["temperature"]);
   me.speedup = getprop("/sim/speed-up");

   # group 4
   flow4kgph = me.groups[me.thegroup["4"]].getChild("flow-kgph").getValue();
   target4degc = me.selectordegc( me.thegroup["4"] );

 
   for( i = 0; i < 3; i = i+1 ) {
        flowkgph = me.groups[i].getChild("flow-kgph").getValue();
        targetdegc = me.selectordegc( i );

        location = "";


        # ===========
        # flight deck
        # ===========
        if( i == me.thegroup["1"] ) {
            # group 1 failed
            if( !me.valves[i].getChild("on").getValue() ) {
                me.closevalve();
            }

            else {
                location = me.thetemperature["1"];
            }
        }


        # =============
        # forward cabin
        # =============
        elsif( i == me.thegroup["2"] ) {
            # group 1 failed
            if( !me.valves[me.thegroup["1"]].getChild("on").getValue() ) {
                location = me.thetemperature["1"];
            }

            # group 2 failed
            elsif( !me.valves[i].getChild("on").getValue() ) {
                me.closevalve();
            }

            else {
                location = me.thetemperature["2"];
            }
        }


        # ==========
        # rear cabin
        # ==========
        elsif( i == me.thegroup["3"] ) {
            # group 1 failed
            if( !me.valves[me.thegroup["1"]].getChild("on").getValue() ) {
                location = me.thetemperature["2"];

                me.control( me.thegroup["4"], me.thetemperature["4"], flow4kgph, target4degc );
            }

            # group 2 failed
            elsif( !me.valves[me.thegroup["2"]].getChild("on").getValue() ) {
                location = me.thetemperature["2"];

                me.control( me.thegroup["4"], me.thetemperature["4"], flow4kgph, target4degc );
            }

            # group 3 + 4 : supposes 1 group is enough
            else {
                location = me.thetemperature["3"];

                # group 3 slaved to rotary selector 4
                if( me.valves[i].getChild("on").getValue() ) {
                    targetdegc = target4degc;
                }

                # group 3 alone
                if( me.is_off( flow4kgph ) ) {
                    me.closevalve();
                    me.adjustvalve( me.thegroup["4"] );
                }

                # group 4 alone
                elsif( me.is_off( flowkgph ) ) {
                     me.control( me.thegroup["4"], location, flow4kgph, target4degc );

                     location = "";

                     me.closevalve();
                     me.adjustvalve( i );
                }

                # group 4
                else {
                     currentdegc = me.conditioning.getChild(location).getValue();
                     targetdegc = me.warmingdegc( flow4kgph, currentdegc, target4degc );

                     me.adjustvalve( me.thegroup["4"] );
                }
            }
        }


        # temperature control
        me.control( i, location, flowkgph, targetdegc );
   }
}

Airconditioning.schedule = func {
   serviceable = me.conditioning.getChild("serviceable").getValue();

   # external air
   me.ramairdegc = getprop(me.noinstrument["temperature"]);

   # ground supply
   groundpsi = me.conditioning.getNode("ground-service").getChild("pressure-psi").getValue();

   for( i = 0; i < 4; i = i+1 ) {
        oldductdegc = me.groups[i].getChild("duct-degc").getValue();

        if( serviceable ) {
            condpsi = me.bleeds[i].getChild("conditioning-psi").getValue();
            if( condpsi < me.MINPSI ) {
                condpsi = groundpsi;
            }
        }
        else {
            condpsi = me.NOPSI;
        }

        if( condpsi >= me.MINPSI ) {
            flowkgph = me.NORMALKGPH;
            inletdegc = me.PRIMARYDEGC;
            ductdegc = me.mixingdegc( i );
        }
        else {
            coef = condpsi / me.MINPSI;

            flowkgph = coef * me.NORMALKGPH;
            inletdegc = me.coolingdegc( coef, me.PRIMARYDEGC );
            ductdegc = me.coolingdegc( coef, oldductdegc );
        }

        result = me.groups[i].getChild("flow-kgph").getValue();
        me.apply("/systems/temperature/group[" ~ i ~ "]/flow-kgph",flowkgph, result);

        # one supposes quick cooling by RAM air, when no mass flow.
        result = me.groups[i].getChild("inlet-degc").getValue();
        me.apply("/systems/temperature/group[" ~ i ~ "]/inlet-degc",inletdegc,result);
        me.apply("/systems/temperature/group[" ~ i ~ "]/duct-degc",ductdegc,oldductdegc);
   }
}

Airconditioning.apply = func( path, value, result ) {
    if( result != value ) {
        interpolate(path,value,me.AIRSEC);
    }
}

Airconditioning.groundservice = func {
    aglft = getprop(me.noinstrument["agl"]);
    speedkt = getprop(me.noinstrument["airspeed"]);

    if( aglft <  15 and speedkt < 15 ) {
        supply = me.conditioning.getNode("ground-service").getChild("door").getValue();

        if( supply ) {
            pressurepsi = me.NOPSI;
        }
        else {
            pressurepsi = me.MINPSI;
        }

        me.conditioning.getNode("ground-service").getChild("door").setValue(!supply);
        me.conditioning.getNode("ground-service").getChild("pressure-psi").setValue(pressurepsi);
    }
}

# connection with delay by ground operator
Airconditioning.door = func {
    aglft = getprop(me.noinstrument["agl"]);
    speedkt = getprop(me.noinstrument["airspeed"]);
    if( aglft >=  15 or speedkt >= 15 ) {

        # door stays open, has forgotten to call for disconnection !
        me.conditioning.getNode("ground-service").getChild("pressure-psi").setValue(me.NOPSI);
    }
}

Airconditioning.control = func( index, location, flowkgph, targetdegc ) {
    if( location != "" ) {
        currentdegc = me.conditioning.getChild(location).getValue();
        targetdegc = me.warmingdegc( flowkgph, currentdegc, targetdegc );

        if( currentdegc != targetdegc ) {
            interpolate("/systems/temperature/" ~ location,targetdegc,me.AIR60SEC);
        }
    }

    me.adjustvalve( index );
}

Airconditioning.is_off = func( flowkgph ) {
   if( flowkgph < me.NORMALKGPH ) {
       result = constant.TRUE;
   }
   else {
       result = constant.FALSE;
   }

   return result;
}

Airconditioning.warmingdegc = func( flowkgph, currentdegc, targetdegc ) {
   off = me.is_off( flowkgph );

   # heat loss
   if( off ) {
       targetdegc = me.ramairdegc;
       stepdegc = me.speedup * me.COOLINGDEGCPMIN;
   }

   # air conditioning
   else {
       stepdegc = me.speedup * me.WARMINGDEGCPMIN;
   }

   diffdegc = targetdegc - currentdegc;

   # warming
   if( diffdegc > stepdegc ) {
       targetdegc = currentdegc + stepdegc;
       me.temperature_valve = me.VALVEH;
   }

   # cooling
   elsif( diffdegc < - stepdegc ) {
       targetdegc = currentdegc - stepdegc;
       me.temperature_valve = me.VALVEC;
   }

   # temperature reached
   else {
       me.temperature_valve = ( targetdegc - me.DUCTMINDEGC ) / me.DUCTDEGC;
   }

   # close valve
   if( off or me.ground_supply ) {
       me.temperature_valve = me.VALVEC;
   }

   return targetdegc;
}

# rough duct temperature
Airconditioning.coolingdegc = func( coef, targetdegc ) {
   resultdegc = me.ramairdegc + coef * ( targetdegc - me.ramairdegc );

   return resultdegc;
}

Airconditioning.mixingdegc = func( index ) {
   valve = me.groups[index].getChild("temperature-valve").getValue();

   # warming
   if( valve == me.VALVEH ) {
       resultdegc = me.DUCTMINDEGC + me.DUCTDEGC;
   }

   # cooling
   elsif( valve == me.VALVEC ) {
       resultdegc = me.DUCTMINDEGC;
   }

   # temperature regulation
   else {
       resultdegc = me.selectordegc( index );
   }

   return resultdegc;
}

Airconditioning.selectordegc = func( index ) {
   selector = me.valves[index].getChild("temperature-selector").getValue();

   # - cold : 5°C.
   # - hot  : 35°C.
   targetdegc = me.DUCTMINDEGC + ( selector / 3.0 ) * me.DUCTDEGC;

   return targetdegc;
}

Airconditioning.closevalve = func {
   me.temperature_valve = me.VALVEC;
}

Airconditioning.adjustvalve = func( index ) {
   result = me.groups[index].getChild("temperature-valve").getValue();
   if( result != me.temperature_valve ) {
       interpolate("/systems/temperature/group[" ~ index ~ "]/temperature-valve",
                   me.temperature_valve, me.VALVESEC);
   }
}

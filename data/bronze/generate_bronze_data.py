"""
Bronze Layer Data Generator
Produces intentionally dirty raw data simulating what arrives from:
  - GA4 BigQuery Export
  - Google Ads via BQ Data Transfer Service
  - Campaign Manager 360 (CM360) via BQ Data Transfer
  - DV360 via BQ Data Transfer
  - YouTube Analytics via BQ Data Transfer

Dirty data includes: nulls, duplicates, format inconsistencies, wrong types,
extra whitespace, negative values, mixed case, encoding artefacts.
Run: python generate_bronze_data.py
"""

import csv, random, os
from datetime import datetime, timedelta

random.seed(42)
OUT = os.path.dirname(__file__)

# ─── helpers ──────────────────────────────────────────────────────────────────
CHANNELS   = ["Organic Search","organic search","ORGANIC_SEARCH","Paid Search","paid search","Display",
               "display","Social","social","Email","email","Direct","direct","(none)",None,""]
CAMPAIGNS  = ["Brand_SA_Q1","brand_sa_q1","BRAND SA Q1","Retargeting_Lapsed","retargeting lapsed",
               "Awareness_Display_ZA","Black Friday 2024","black friday","","UNKNOWN",None]
DEVICES    = ["desktop","DESKTOP","Desktop","mobile","Mobile","MOBILE","tablet","Tablet",None,""]
COUNTRIES  = ["South Africa","south africa","ZA","za","RSA","rsa"," South Africa",None,""]
EVENTS     = ["page_view","session_start","purchase","add_to_cart","begin_checkout","scroll",
               "click","file_download","video_start","search","login","sign_up"]
AD_FORMATS = ["Text Ad","text ad","TEXT_AD","Responsive Display","responsive_display",None,""]
CURRENCIES = ["ZAR","zar","USD","usd","ZAR ","ZAR\t",None]

def rand_date(start="2024-01-01", end="2024-12-31"):
    s = datetime.strptime(start,"%Y-%m-%d")
    e = datetime.strptime(end,"%Y-%m-%d")
    d = s + timedelta(days=random.randint(0,(e-s).days))
    # dirty formats
    fmt = random.choice(["%Y-%m-%d","%d/%m/%Y","%d-%m-%Y","%Y%m%d","%B %d, %Y"])
    return d.strftime(fmt)

def dirty_str(s):
    if s is None: return ""
    ops = [lambda x:x, lambda x:x.upper(), lambda x:x.lower(),
           lambda x:" "+x, lambda x:x+" ", lambda x:x.replace(" ","_")]
    return random.choice(ops)(s)

def maybe_null(v, p=0.08):
    return "" if random.random()<p else v

# ─── GA4 Events (Bronze) ──────────────────────────────────────────────────────
def gen_ga4(n=5000):
    path = os.path.join(OUT,"ga4_events_raw.csv")
    fields = ["event_date","event_timestamp","event_name","user_pseudo_id",
              "session_id","geo_country","geo_city","device_category",
              "traffic_source_medium","traffic_source_source","traffic_source_name",
              "page_location","page_title","event_value_in_usd","ga_session_number",
              "user_first_touch_timestamp","is_active_user","platform","stream_id"]
    rows=[]
    for i in range(n):
        uid = f"user_{random.randint(1,800):05d}"
        rows.append({
            "event_date":       maybe_null(rand_date()),
            "event_timestamp":  maybe_null(str(random.randint(1700000000000000,1800000000000000)) if random.random()>.05 else str(random.randint(1000,9999))),
            "event_name":       maybe_null(random.choice(EVENTS)),
            "user_pseudo_id":   maybe_null(uid,0.02),
            "session_id":       maybe_null(str(random.randint(1,9999999)),0.04),
            "geo_country":      maybe_null(random.choice(COUNTRIES),0.12),
            "geo_city":         maybe_null(random.choice(["Cape Town","Johannesburg","Durban","Pretoria","Port Elizabeth",None,""]),0.15),
            "device_category":  maybe_null(random.choice(DEVICES),0.05),
            "traffic_source_medium":  maybe_null(random.choice(CHANNELS),0.10),
            "traffic_source_source":  maybe_null(random.choice(["google","Google","GOOGLE","(direct)","facebook","bing","newsletter",None,""]),0.10),
            "traffic_source_name":    maybe_null(random.choice(CAMPAIGNS),0.20),
            "page_location":    maybe_null(random.choice(["/","/products","/checkout","/thankyou","/blog/"+str(random.randint(1,50)),None]),0.05),
            "page_title":       maybe_null(random.choice(["Home","Product Page","Checkout","Thank You","Blog","",None]),0.08),
            "event_value_in_usd": maybe_null(str(round(random.uniform(-5,999),2)) if random.random()>.9 else (str(round(random.uniform(0,999),2)) if random.random()>.1 else ""),0.30),
            "ga_session_number": maybe_null(str(random.randint(-1,50)),0.05),
            "user_first_touch_timestamp": maybe_null(str(random.randint(1700000000000000,1800000000000000)),0.10),
            "is_active_user":   maybe_null(random.choice(["true","True","TRUE","1","false","False","FALSE","0",None]),0.05),
            "platform":         maybe_null(random.choice(["WEB","web","Web","ANDROID","IOS",None]),0.05),
            "stream_id":        maybe_null(str(random.randint(100000000,999999999)),0.03),
        })
    # inject duplicates (~3%)
    dups = random.sample(rows, int(n*0.03))
    rows.extend(dups)
    random.shuffle(rows)
    with open(path,"w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    print(f"GA4 bronze: {len(rows)} rows → {path}")

# ─── Google Ads (Bronze) ──────────────────────────────────────────────────────
def gen_google_ads(n=2000):
    path = os.path.join(OUT,"google_ads_raw.csv")
    fields = ["date","customer_id","campaign_id","campaign_name","campaign_status",
              "ad_group_id","ad_group_name","keyword_text","match_type",
              "impressions","clicks","cost_micros","conversions","conversion_value",
              "currency_code","device","network","geo_target"]
    rows=[]
    for _ in range(n):
        impr = random.randint(-10,100000)  # negatives = dirty
        clicks = random.randint(0,max(1,abs(impr)//10))
        cost = clicks * random.uniform(0.5,15)
        rows.append({
            "date":              maybe_null(rand_date()),
            "customer_id":       maybe_null(str(random.randint(1000000000,9999999999)),0.02),
            "campaign_id":       maybe_null(str(random.randint(100000,999999)),0.02),
            "campaign_name":     maybe_null(dirty_str(random.choice([c for c in CAMPAIGNS if c])),0.05),
            "campaign_status":   maybe_null(random.choice(["ENABLED","enabled","PAUSED","paused","REMOVED",None]),0.04),
            "ad_group_id":       maybe_null(str(random.randint(10000,999999)),0.03),
            "ad_group_name":     maybe_null(random.choice(["Brand Keywords","Competitor","Generic","Remarketing","DSA",None]),0.08),
            "keyword_text":      maybe_null(random.choice(["pargo parcels","parcel pickup","collection point","locker delivery",None,""]),0.15),
            "match_type":        maybe_null(random.choice(["EXACT","exact","BROAD","broad","PHRASE","phrase",None]),0.10),
            "impressions":       str(impr),
            "clicks":            str(clicks),
            "cost_micros":       maybe_null(str(int(cost*1_000_000)),0.05),
            "conversions":       maybe_null(str(round(random.uniform(0,clicks*0.1),2)),0.10),
            "conversion_value":  maybe_null(str(round(random.uniform(0,5000),2)) if random.random()>.3 else "",0.15),
            "currency_code":     maybe_null(random.choice(CURRENCIES),0.05),
            "device":            maybe_null(random.choice(DEVICES),0.06),
            "network":           maybe_null(random.choice(["SEARCH","search","DISPLAY","display","YOUTUBE","youtube",None]),0.05),
            "geo_target":        maybe_null(random.choice(COUNTRIES),0.08),
        })
    dups = random.sample(rows, int(n*0.04))
    rows.extend(dups)
    random.shuffle(rows)
    with open(path,"w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    print(f"Google Ads bronze: {len(rows)} rows → {path}")

# ─── CM360 (Bronze) ───────────────────────────────────────────────────────────
def gen_cm360(n=2000):
    path = os.path.join(OUT,"cm360_raw.csv")
    fields = ["date","advertiser_id","advertiser_name","campaign_id","campaign_name",
              "placement_id","placement_name","ad_id","ad_name","creative_type",
              "impressions","clicks","click_through_conversions","view_through_conversions",
              "total_conversions","revenue","dma_region","country"]
    rows=[]
    for _ in range(n):
        impr = random.randint(0,500000)
        clicks = int(impr * random.uniform(0,0.02))
        rows.append({
            "date":                      maybe_null(rand_date()),
            "advertiser_id":             maybe_null(str(random.randint(100000,999999)),0.02),
            "advertiser_name":           maybe_null(dirty_str("PenBev"),0.03),
            "campaign_id":               str(random.randint(10000,99999)),
            "campaign_name":             maybe_null(dirty_str(random.choice([c for c in CAMPAIGNS if c])),0.05),
            "placement_id":              str(random.randint(100000,999999)),
            "placement_name":            maybe_null(random.choice(["300x250 SA News","728x90 Mobile","Interstitial","Native Feed",None]),0.10),
            "ad_id":                     str(random.randint(1000000,9999999)),
            "ad_name":                   maybe_null(random.choice(["Brand_v1","Promo_Q4","Retargeting_v2",None,""]),0.10),
            "creative_type":             maybe_null(dirty_str(random.choice(["DISPLAY","RICH_MEDIA","VIDEO","HTML5",None])),0.08),
            "impressions":               str(impr),
            "clicks":                    str(clicks),
            "click_through_conversions": maybe_null(str(random.randint(0,max(1,clicks//10))),0.12),
            "view_through_conversions":  maybe_null(str(random.randint(0,max(1,impr//1000))),0.15),
            "total_conversions":         maybe_null(str(random.randint(0,100)),0.10),
            "revenue":                   maybe_null(str(round(random.uniform(-100,50000),2)),0.15),
            "dma_region":                maybe_null(random.choice(["Cape Town","Johannesburg","Durban",None,""]),0.20),
            "country":                   maybe_null(random.choice(COUNTRIES),0.08),
        })
    dups = random.sample(rows, int(n*0.05))
    rows.extend(dups)
    random.shuffle(rows)
    with open(path,"w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    print(f"CM360 bronze: {len(rows)} rows → {path}")

# ─── DV360 (Bronze) ───────────────────────────────────────────────────────────
def gen_dv360(n=2000):
    path = os.path.join(OUT,"dv360_raw.csv")
    fields = ["date","partner_id","advertiser_id","campaign_id","insertion_order_id",
              "insertion_order_name","line_item_id","line_item_name","line_item_type",
              "targeting_type","audience_segment","impressions","clicks","revenue_usd",
              "total_conversions","view_rate","average_cpm","exchange"]
    rows=[]
    for _ in range(n):
        impr = random.randint(0,1000000)
        rows.append({
            "date":                 maybe_null(rand_date()),
            "partner_id":           maybe_null(str(random.randint(1000,9999)),0.02),
            "advertiser_id":        maybe_null(str(random.randint(100000,999999)),0.02),
            "campaign_id":          str(random.randint(10000,99999)),
            "insertion_order_id":   str(random.randint(100000,999999)),
            "insertion_order_name": maybe_null(dirty_str(random.choice(["IO_Brand_Awareness","IO_Retargeting","IO_Prospecting",None])),0.08),
            "line_item_id":         str(random.randint(1000000,9999999)),
            "line_item_name":       maybe_null(random.choice(["LI_Desktop_SA","LI_Mobile_ZA","LI_YouTube_PreRoll",None,""]),0.10),
            "line_item_type":       maybe_null(random.choice(["DISPLAY","VIDEO","AUDIO","NATIVE",None]),0.06),
            "targeting_type":       maybe_null(random.choice(["AUDIENCE","CONTEXTUAL","GEO","KEYWORD",None]),0.08),
            "audience_segment":     maybe_null(random.choice(["In-market: Electronics","Similar Audiences","Remarketing",None,""]),0.20),
            "impressions":          str(impr),
            "clicks":               str(int(impr * random.uniform(0,0.005))),
            "revenue_usd":          maybe_null(str(round(random.uniform(-50,impr*0.001),4)),0.10),
            "total_conversions":    maybe_null(str(random.randint(0,500)),0.15),
            "view_rate":            maybe_null(str(round(random.uniform(-0.05,1.05),4)),0.10),
            "average_cpm":          maybe_null(str(round(random.uniform(0,25),2)),0.08),
            "exchange":             maybe_null(random.choice(["Google AdX","AdX","GOOGLE","OpenX","Index Exchange",None]),0.06),
        })
    dups = random.sample(rows, int(n*0.04))
    rows.extend(dups)
    random.shuffle(rows)
    with open(path,"w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    print(f"DV360 bronze: {len(rows)} rows → {path}")

# ─── YouTube Analytics (Bronze) ───────────────────────────────────────────────
def gen_youtube(n=1500):
    path = os.path.join(OUT,"youtube_raw.csv")
    fields = ["date","channel_id","video_id","video_title","country","device_type",
              "traffic_source_type","views","watch_time_minutes","average_view_duration",
              "impressions","impressions_click_through_rate","likes","comments",
              "shares","subscribers_gained","estimated_revenue_usd"]
    rows=[]
    for _ in range(n):
        views = random.randint(0,100000)
        rows.append({
            "date":                          maybe_null(rand_date()),
            "channel_id":                    maybe_null("UC"+str(random.randint(10**20,10**21-1)),0.02),
            "video_id":                      maybe_null("".join(random.choices("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",k=11)),0.03),
            "video_title":                   maybe_null(random.choice(["How It Works","Brand Story 2024","Product Demo","Customer Testimonial","",None]),0.08),
            "country":                       maybe_null(random.choice(COUNTRIES),0.10),
            "device_type":                   maybe_null(dirty_str(random.choice(["MOBILE","DESKTOP","TABLET","TV","UNKNOWN",None])),0.06),
            "traffic_source_type":           maybe_null(random.choice(["YT_SEARCH","SUGGESTED","BROWSE","EXTERNAL","PLAYLIST",None]),0.08),
            "views":                         str(views),
            "watch_time_minutes":            maybe_null(str(round(random.uniform(-10, views*3),1)),0.08),
            "average_view_duration":         maybe_null(str(round(random.uniform(0,600),1)),0.10),
            "impressions":                   maybe_null(str(random.randint(0,views*10)),0.05),
            "impressions_click_through_rate":maybe_null(str(round(random.uniform(-0.01,0.25),4)),0.12),
            "likes":                         maybe_null(str(random.randint(0,views//5)),0.08),
            "comments":                      maybe_null(str(random.randint(0,views//20)),0.15),
            "shares":                        maybe_null(str(random.randint(0,views//10)),0.10),
            "subscribers_gained":            maybe_null(str(random.randint(-50,views//100)),0.10),
            "estimated_revenue_usd":         maybe_null(str(round(random.uniform(-1, views*0.005),4)),0.20),
        })
    dups = random.sample(rows, int(n*0.03))
    rows.extend(dups)
    random.shuffle(rows)
    with open(path,"w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    print(f"YouTube bronze: {len(rows)} rows → {path}")

if __name__ == "__main__":
    gen_ga4();  gen_google_ads(); gen_cm360(); gen_dv360(); gen_youtube()
    print("\nAll bronze files generated. Known issues injected:")
    print("  • Null/empty values (8-20% per column)")
    print("  • Duplicate rows (3-5%)")
    print("  • Mixed date formats (YYYY-MM-DD / DD/MM/YYYY / Month D, YYYY / YYYYMMDD)")
    print("  • Mixed case & encoding (Google/GOOGLE/google, ZA/South Africa/south africa)")
    print("  • Negative values in numeric fields (impressions, revenue, CTR)")
    print("  • Wrong data types (bool stored as text, timestamps as short ints)")
    print("  • Extra whitespace leading/trailing in text fields")

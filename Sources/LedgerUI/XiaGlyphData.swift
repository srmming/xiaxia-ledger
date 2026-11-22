// 自动生成：design/icon-kit/build.py。别手改，改 design/icon-kit/icons.py 或 illos.py 再跑一次。
// 夏夏账本自己画的图标（原创）：每个图标是几层路径，层的颜料见 XiaIcons.swift 里的 XiaRenderer。
import CoreGraphics

enum XiaGlyph: String, CaseIterable, Sendable {
    case dining = "dining"
    case grocery = "grocery"
    case transport = "transport"
    case housing = "housing"
    case utilities = "utilities"
    case shopping = "shopping"
    case entertainment = "entertainment"
    case medical = "medical"
    case phone = "phone"
    case travel = "travel"
    case baby = "baby"
    case other = "other"
    case clothing = "clothing"
    case gift = "gift"
    case coffee = "coffee"
    case fuel = "fuel"
    case pets = "pets"
    case education = "education"
    case beauty = "beauty"
    case nails = "nails"
    case subscription = "subscription"
    case insurance = "insurance"
    case tax = "tax"
    case social = "social"
    case fee = "fee"
    case refund = "refund"
    case salary = "salary"
    case income = "income"
    case revenue = "revenue"
    case shoprent = "shoprent"
    case supplies = "supplies"
    case equipment = "equipment"
    case staff = "staff"
    case marketing = "marketing"
    case topup = "topup"
    case transfer = "transfer"
    case withdraw = "withdraw"
    case savings = "savings"
    case invest = "invest"
    case loan = "loan"
    case repay = "repay"
    case sport = "sport"
    case home = "home"
    case snacks = "snacks"
    case digital = "digital"
    case uncategorized = "uncategorized"
    case bank = "bank"
    case credit = "credit"
    case cash = "cash"
    case wallet = "wallet"
    case stash = "stash"
    case navOverview = "nav.overview"
    case navSpending = "nav.spending"
    case navTrends = "nav.trends"
    case navWealth = "nav.wealth"
    case navPlans = "nav.plans"
    case navXiaxia = "nav.xiaxia"
    case navChanges = "nav.changes"
    case navTransactions = "nav.transactions"
    case navSettings = "nav.settings"
    case actAdd = "act.add"
    case actAsk = "act.ask"
    case actChat = "act.chat"
    case actEdit = "act.edit"
    case actDelete = "act.delete"
    case actUndo = "act.undo"
    case actSearch = "act.search"
    case actFilter = "act.filter"
    case actCopy = "act.copy"
    case actImport = "act.import"
    case actExport = "act.export"
    case actSync = "act.sync"
    case actHide = "act.hide"
    case actShow = "act.show"
    case actCalendar = "act.calendar"
    case actBooks = "act.books"
    case actMore = "act.more"
    case actClose = "act.close"
    case actCheck = "act.check"
    case actLink = "act.link"
    case actLock = "act.lock"
    case actBell = "act.bell"
    case actScan = "act.scan"
    case actShare = "act.share"
    case badgeAi = "badge.ai"
    case badgeMe = "badge.me"
    case badgeWarn = "badge.warn"
    case badgeAlert = "badge.alert"
    case badgeDone = "badge.done"
    case badgeRepeat = "badge.repeat"
    case badgeNew = "badge.new"
    case badgeSynced = "badge.synced"
    case badgeOffline = "badge.offline"
    case badgePrivate = "badge.private"
    case delivery = "delivery"
    case breakfast = "breakfast"
    case fruit = "fruit"
    case dessert = "dessert"
    case bubbletea = "bubbletea"
    case drinks = "drinks"
    case veggies = "veggies"
    case bakery = "bakery"
    case hotpot = "hotpot"
    case taxi = "taxi"
    case metro = "metro"
    case flight = "flight"
    case train = "train"
    case parking = "parking"
    case bike = "bike"
    case carcare = "carcare"
    case toll = "toll"
    case mortgage = "mortgage"
    case internet = "internet"
    case gas = "gas"
    case water = "water"
    case power = "power"
    case appliance = "appliance"
    case repair = "repair"
    case cleaning = "cleaning"
    case plants = "plants"
    case property = "property"
    case cosmetics = "cosmetics"
    case shoes = "shoes"
    case handbag = "handbag"
    case jewelry = "jewelry"
    case glasses = "glasses"
    case books = "books"
    case stationery = "stationery"
    case toys = "toys"
    case online = "online"
    case dental = "dental"
    case pharmacy = "pharmacy"
    case checkup = "checkup"
    case skincare = "skincare"
    case haircut = "haircut"
    case spa = "spa"
    case gym = "gym"
    case movie = "movie"
    case music = "music"
    case ticket = "ticket"
    case camera = "camera"
    case bar = "bar"
    case karaoke = "karaoke"
    case hobby = "hobby"
    case hotel = "hotel"
    case visa = "visa"
    case redpacket = "redpacket"
    case family = "family"
    case donation = "donation"
    case wedding = "wedding"
    case elderly = "elderly"
    case school = "school"
    case babycare = "babycare"
    case course = "course"
    case office = "office"
    case software = "software"
    case website = "website"
    case sidejob = "sidejob"
    case bonus = "bonus"
    case reimburse = "reimburse"
    case rentincome = "rentincome"
    case resale = "resale"
    case interest = "interest"
    case taxrefund = "taxrefund"
    case cardpay = "cardpay"
    case installment = "installment"
    case exchange = "exchange"
    case stocks = "stocks"
    case fine = "fine"
    case bankfee = "bankfee"
    case remit = "remit"
    case debt = "debt"
    case crypto = "crypto"
    case shipping = "shipping"
    case platformfee = "platformfee"
    case pos = "pos"
    case renovation = "renovation"
    case accounting = "accounting"
    case rentEquip = "rent-equip"
    case uniform = "uniform"
    case license = "license"
    case customer = "customer"
    case star = "star"
    case heart = "heart"
    case emergency = "emergency"
    case celebrate = "celebrate"
    case illoLedger = "illo.ledger"
    case illoMonth = "illo.month"
    case illoSpending = "illo.spending"
    case illoTrends = "illo.trends"
    case illoAccounts = "illo.accounts"
    case illoPlans = "illo.plans"
    case illoSearch = "illo.search"
    case illoConnect = "illo.connect"
    case illoError = "illo.error"
    case illoDone = "illo.done"
    case illoLoading = "illo.loading"
}

extension XiaGlyph {
    /// 画布大小（图标 24×24，插画 160×120）。
    var canvas: CGSize {
        switch self {
        case .dining, .grocery, .transport, .housing, .utilities, .shopping, .entertainment, .medical, .phone, .travel, .baby, .other, .clothing, .gift, .coffee, .fuel, .pets, .education, .beauty, .nails, .subscription, .insurance, .tax, .social, .fee, .refund, .salary, .income, .revenue, .shoprent, .supplies, .equipment, .staff, .marketing, .topup, .transfer, .withdraw, .savings, .invest, .loan, .repay, .sport, .home, .snacks, .digital, .uncategorized, .bank, .credit, .cash, .wallet, .stash, .navOverview, .navSpending, .navTrends, .navWealth, .navPlans, .navXiaxia, .navChanges, .navTransactions, .navSettings, .actAdd, .actAsk, .actChat, .actEdit, .actDelete, .actUndo, .actSearch, .actFilter, .actCopy, .actImport, .actExport, .actSync, .actHide, .actShow, .actCalendar, .actBooks, .actMore, .actClose, .actCheck, .actLink, .actLock, .actBell, .actScan, .actShare, .badgeAi, .badgeMe, .badgeWarn, .badgeAlert, .badgeDone, .badgeRepeat, .badgeNew, .badgeSynced, .badgeOffline, .badgePrivate, .delivery, .breakfast, .fruit, .dessert, .bubbletea, .drinks, .veggies, .bakery, .hotpot, .taxi, .metro, .flight, .train, .parking, .bike, .carcare, .toll, .mortgage, .internet, .gas, .water, .power, .appliance, .repair, .cleaning, .plants, .property, .cosmetics, .shoes, .handbag, .jewelry, .glasses, .books, .stationery, .toys, .online, .dental, .pharmacy, .checkup, .skincare, .haircut, .spa, .gym, .movie, .music, .ticket, .camera, .bar, .karaoke, .hobby, .hotel, .visa, .redpacket, .family, .donation, .wedding, .elderly, .school, .babycare, .course, .office, .software, .website, .sidejob, .bonus, .reimburse, .rentincome, .resale, .interest, .taxrefund, .cardpay, .installment, .exchange, .stocks, .fine, .bankfee, .remit, .debt, .crypto, .shipping, .platformfee, .pos, .renovation, .accounting, .rentEquip, .uniform, .license, .customer, .star, .heart, .emergency, .celebrate: CGSize(width: 24, height: 24)
        case .illoLedger, .illoMonth, .illoSpending, .illoTrends, .illoAccounts, .illoPlans, .illoSearch, .illoConnect, .illoError, .illoDone, .illoLoading: CGSize(width: 160, height: 120)
        }
    }

    /// 自带的颜色（分类、账户、徽章）；nil = 跟着文字颜色。
    var tint: String? {
        switch self {
        case .dining, .family, .customer: "FF7A59"
        case .grocery: "23A794"
        case .transport, .transfer, .bank, .metro, .remit: "4C8DF6"
        case .housing, .shoprent, .donation, .renovation, .heart: "F2667A"
        case .utilities: "EFAA00"
        case .shopping, .karaoke, .wedding: "EC5BA8"
        case .entertainment, .marketing, .wallet: "FF8F3D"
        case .medical, .checkup: "FF6B81"
        case .phone, .loan, .glasses, .haircut, .course: "7B7FF2"
        case .travel, .topup, .flight, .water, .jewelry, .dental, .exchange: "24ABEB"
        case .baby, .babycare: "FF9E7A"
        case .other, .uncategorized: "98A2B3"
        case .clothing: "E36BC4"
        case .gift, .credit, .handbag, .bar, .cardpay: "C86EF0"
        case .coffee: "B98060"
        case .fuel, .toll, .repair, .stationery, .crypto: "F7A21B"
        case .pets, .toys: "C98A45"
        case .education, .books, .school, .accounting: "3F7BF0"
        case .beauty: "F47BB8"
        case .nails, .cosmetics: "F062A2"
        case .subscription, .staff, .music, .installment, .platformfee: "9C7CF4"
        case .insurance, .train, .cleaning, .spa, .hobby, .website, .resale: "2FB7A4"
        case .tax, .carcare, .office, .license: "7A879C"
        case .social, .withdraw, .appliance, .camera, .pos: "6E8BC2"
        case .fee, .bankfee: "8E99AD"
        case .refund, .invest, .repay, .pharmacy, .visa, .reimburse, .taxrefund: "2DB884"
        case .salary, .income, .revenue, .cash, .sidejob, .rentincome, .interest: "22A861"
        case .supplies, .skincare, .uniform: "F48FB1"
        case .equipment, .rentEquip: "26A69A"
        case .savings: "F98DB0"
        case .sport, .veggies, .bike, .plants: "3DBE6B"
        case .home, .stash, .bakery, .elderly: "D9A05B"
        case .snacks, .dessert, .celebrate: "FF7FA8"
        case .digital, .parking, .internet, .shoes, .hotel, .software: "5B8DEF"
        case .badgeAi, .badgeRepeat: "ai"
        case .badgeMe: "fg2"
        case .badgeWarn: "warn"
        case .badgeAlert: "alert"
        case .badgeDone, .badgeSynced: "income"
        case .badgeNew, .badgePrivate: "brand"
        case .badgeOffline: "fg3"
        case .delivery, .online, .gym, .ticket, .shipping: "FF8A3D"
        case .breakfast: "F5A524"
        case .fruit, .hotpot, .movie, .stocks: "F2556B"
        case .bubbletea: "C98A5A"
        case .drinks: "B5527A"
        case .taxi, .power, .bonus, .star: "F5B300"
        case .mortgage: "E8505B"
        case .gas: "FF7A3D"
        case .property: "8E7CF4"
        case .redpacket, .emergency: "E8414E"
        case .fine, .debt: "E8A000"
        default: nil
        }
    }

    /// 给人看的名字（无障碍朗读也用）。
    var label: String {
        switch self {
        case .dining: "餐饮"
        case .grocery: "超市"
        case .transport: "交通"
        case .housing: "房租"
        case .utilities: "水电"
        case .shopping: "购物"
        case .entertainment: "娱乐"
        case .medical: "医疗"
        case .phone: "通讯"
        case .travel: "旅行"
        case .baby: "宝宝"
        case .other: "其他"
        case .clothing: "衣服"
        case .gift: "礼物"
        case .coffee: "咖啡"
        case .fuel: "加油"
        case .pets: "宠物"
        case .education: "学习"
        case .beauty: "美容"
        case .nails: "美甲"
        case .subscription: "订阅"
        case .insurance: "保险"
        case .tax: "税费"
        case .social: "社保"
        case .fee: "手续费"
        case .refund: "退款"
        case .salary: "工资"
        case .income: "收入"
        case .revenue: "营业收入"
        case .shoprent: "店租"
        case .supplies: "耗材"
        case .equipment: "设备"
        case .staff: "员工工资"
        case .marketing: "营销"
        case .topup: "充值"
        case .transfer: "转账"
        case .withdraw: "老板提款"
        case .savings: "储蓄"
        case .invest: "投资"
        case .loan: "借款"
        case .repay: "还款"
        case .sport: "运动"
        case .home: "家居"
        case .snacks: "零食"
        case .digital: "数码"
        case .uncategorized: "未分类"
        case .bank: "银行卡"
        case .credit: "信用卡"
        case .cash: "现金"
        case .wallet: "电子钱包"
        case .stash: "私房钱"
        case .navOverview: "总览"
        case .navSpending: "花销"
        case .navTrends: "趋势"
        case .navWealth: "家底"
        case .navPlans: "计划"
        case .navXiaxia: "夏夏"
        case .navChanges: "改动记录"
        case .navTransactions: "流水"
        case .navSettings: "设置"
        case .actAdd: "记一笔"
        case .actAsk: "问夏夏"
        case .actChat: "对话"
        case .actEdit: "改"
        case .actDelete: "删除"
        case .actUndo: "撤销"
        case .actSearch: "搜索"
        case .actFilter: "筛选"
        case .actCopy: "复制"
        case .actImport: "导入"
        case .actExport: "导出"
        case .actSync: "同步"
        case .actHide: "藏起来"
        case .actShow: "显示"
        case .actCalendar: "月份"
        case .actBooks: "账本"
        case .actMore: "更多"
        case .actClose: "关掉"
        case .actCheck: "好了"
        case .actLink: "连上"
        case .actLock: "锁"
        case .actBell: "提醒"
        case .actScan: "拍小票"
        case .actShare: "分享"
        case .badgeAi: "AI 记的"
        case .badgeMe: "你记的"
        case .badgeWarn: "留意"
        case .badgeAlert: "要处理"
        case .badgeDone: "做到了"
        case .badgeRepeat: "每月扣"
        case .badgeNew: "新"
        case .badgeSynced: "已同步"
        case .badgeOffline: "没连上"
        case .badgePrivate: "私房钱"
        case .delivery: "外卖"
        case .breakfast: "早餐"
        case .fruit: "水果"
        case .dessert: "甜品"
        case .bubbletea: "奶茶"
        case .drinks: "喝酒"
        case .veggies: "买菜"
        case .bakery: "面包"
        case .hotpot: "火锅"
        case .taxi: "打车"
        case .metro: "地铁"
        case .flight: "机票"
        case .train: "火车"
        case .parking: "停车"
        case .bike: "单车"
        case .carcare: "修车"
        case .toll: "过路费"
        case .mortgage: "房贷"
        case .internet: "网费"
        case .gas: "燃气"
        case .water: "水费"
        case .power: "电费"
        case .appliance: "家电"
        case .repair: "维修"
        case .cleaning: "清洁"
        case .plants: "绿植"
        case .property: "物业"
        case .cosmetics: "化妆品"
        case .shoes: "鞋子"
        case .handbag: "包包"
        case .jewelry: "首饰"
        case .glasses: "眼镜"
        case .books: "书"
        case .stationery: "文具"
        case .toys: "玩具"
        case .online: "网购"
        case .dental: "看牙"
        case .pharmacy: "买药"
        case .checkup: "体检"
        case .skincare: "护肤"
        case .haircut: "理发"
        case .spa: "按摩"
        case .gym: "健身房"
        case .movie: "电影"
        case .music: "音乐"
        case .ticket: "门票"
        case .camera: "摄影"
        case .bar: "酒吧"
        case .karaoke: "唱歌"
        case .hobby: "爱好"
        case .hotel: "酒店"
        case .visa: "证件"
        case .redpacket: "红包"
        case .family: "家人"
        case .donation: "捐款"
        case .wedding: "婚礼"
        case .elderly: "父母"
        case .school: "学费"
        case .babycare: "母婴"
        case .course: "课程"
        case .office: "办公"
        case .software: "软件"
        case .website: "网站"
        case .sidejob: "副业"
        case .bonus: "奖金"
        case .reimburse: "报销"
        case .rentincome: "租金收入"
        case .resale: "二手"
        case .interest: "利息"
        case .taxrefund: "退税"
        case .cardpay: "还信用卡"
        case .installment: "分期"
        case .exchange: "换汇"
        case .stocks: "股票"
        case .fine: "罚款"
        case .bankfee: "银行费"
        case .remit: "汇款"
        case .debt: "欠款"
        case .crypto: "数字货币"
        case .shipping: "快递"
        case .platformfee: "平台佣金"
        case .pos: "刷卡费"
        case .renovation: "装修"
        case .accounting: "会计"
        case .rentEquip: "租设备"
        case .uniform: "工作服"
        case .license: "执照"
        case .customer: "客人"
        case .star: "心愿"
        case .heart: "喜欢"
        case .emergency: "应急"
        case .celebrate: "节日"
        case .illoLedger: "账本还是空的"
        case .illoMonth: "这个月还没有流水"
        case .illoSpending: "还没花钱"
        case .illoTrends: "流水还不够看趋势"
        case .illoAccounts: "还没有账户"
        case .illoPlans: "还没有计划"
        case .illoSearch: "没找到"
        case .illoConnect: "还没连上 AI"
        case .illoError: "出了点问题"
        case .illoDone: "都处理好了"
        case .illoLoading: "正在读"
        }
    }

    /// (颜料, 路径, 描边宽度；0 = 填充)
    var layers: [(String, String, Double)] {
        switch self {
        case .dining: [
            ("solid", "M 14.2 2.8 L 19.6 9.6", 1.6),
            ("solid", "M 17.6 2.4 L 21.2 8.6", 1.6),
            ("soft", "M 19.2 11.2 C 19.2 13.08 15.98 14.6 12 14.6 C 8.02 14.6 4.8 13.08 4.8 11.2 C 4.8 9.32 8.02 7.8 12 7.8 C 15.98 7.8 19.2 9.32 19.2 11.2 Z", 0),
            ("solid", "M 3 11.5 L 21 11.5 C 21 16.8 17.2 20.5 12 20.5 C 6.8 20.5 3 16.8 3 11.5 Z", 0),
            ("solid", "M 10.5 19.4 L 13.5 19.4 C 14 19.4 14.4 19.8 14.4 20.3 L 14.4 20.3 C 14.4 20.8 14 21.2 13.5 21.2 L 10.5 21.2 C 10 21.2 9.6 20.8 9.6 20.3 L 9.6 20.3 C 9.6 19.8 10 19.4 10.5 19.4 Z", 0),
            ("hi", "M 8.44 17.08 C 7.4 16.35 6.61 15.32 6.17 14.12", 1.3),
            ("hi", "M 9.9 9.4 C 9.9 9.9 9.5 10.3 9 10.3 C 8.5 10.3 8.1 9.9 8.1 9.4 C 8.1 8.9 8.5 8.5 9 8.5 C 9.5 8.5 9.9 8.9 9.9 9.4 Z", 0),
        ]
        case .grocery: [
            ("soft", "M 12.2 6.6 C 12.2 8.04 11.04 9.2 9.6 9.2 C 8.16 9.2 7 8.04 7 6.6 C 7 5.16 8.16 4 9.6 4 C 11.04 4 12.2 5.16 12.2 6.6 Z", 0),
            ("soft", "M 15.19 3.36 L 15.19 3.36 C 16.03 3.63 16.49 4.53 16.22 5.37 L 15.23 8.42 C 14.95 9.26 14.05 9.72 13.21 9.44 L 13.21 9.44 C 12.37 9.17 11.91 8.27 12.18 7.43 L 13.17 4.38 C 13.45 3.54 14.35 3.08 15.19 3.36 Z", 0),
            ("solid", "M 5.8 10.15 C 5.55 9.19 6.01 8.6 7 8.6 L 19.6 8.6 C 20.59 8.6 21.03 9.18 20.76 10.14 L 19.64 14.06 C 19.37 15.02 18.59 15.6 17.6 15.6 L 8.8 15.6 C 7.81 15.6 7.05 15.01 6.8 14.05 Z", 0),
            ("solid", "M 2.4 4.2 L 4.4 4.2 L 6.8 15.6 L 18.6 15.6", 1.7),
            ("solid", "M 10.2 19.4 C 10.2 20.39 9.39 21.2 8.4 21.2 C 7.41 21.2 6.6 20.39 6.6 19.4 C 6.6 18.41 7.41 17.6 8.4 17.6 C 9.39 17.6 10.2 18.41 10.2 19.4 Z", 0),
            ("solid", "M 19 19.4 C 19 20.39 18.19 21.2 17.2 21.2 C 16.21 21.2 15.4 20.39 15.4 19.4 C 15.4 18.41 16.21 17.6 17.2 17.6 C 18.19 17.6 19 18.41 19 19.4 Z", 0),
            ("hi", "M 9.6 11.2 L 17.6 11.2", 1.3),
        ]
        case .transport: [
            ("solid", "M 7.7 17 L 8.1 17 C 8.82 17 9.4 17.58 9.4 18.3 L 9.4 19.9 C 9.4 20.62 8.82 21.2 8.1 21.2 L 7.7 21.2 C 6.98 21.2 6.4 20.62 6.4 19.9 L 6.4 18.3 C 6.4 17.58 6.98 17 7.7 17 Z", 0),
            ("solid", "M 15.9 17 L 16.3 17 C 17.02 17 17.6 17.58 17.6 18.3 L 17.6 19.9 C 17.6 20.62 17.02 21.2 16.3 21.2 L 15.9 21.2 C 15.18 21.2 14.6 20.62 14.6 19.9 L 14.6 18.3 C 14.6 17.58 15.18 17 15.9 17 Z", 0),
            ("soft", "M 8.6 3 L 15.4 3 C 17.94 3 20 5.06 20 7.6 L 20 14.4 C 20 16.94 17.94 19 15.4 19 L 8.6 19 C 6.06 19 4 16.94 4 14.4 L 4 7.6 C 4 5.06 6.06 3 8.6 3 Z", 0),
            ("solid", "M 8.2 5.4 L 15.8 5.4 C 16.9 5.4 17.8 6.3 17.8 7.4 L 17.8 10 C 17.8 11.1 16.9 12 15.8 12 L 8.2 12 C 7.1 12 6.2 11.1 6.2 10 L 6.2 7.4 C 6.2 6.3 7.1 5.4 8.2 5.4 Z", 0),
            ("solid", "M 9.6 15.2 C 9.6 15.97 8.97 16.6 8.2 16.6 C 7.43 16.6 6.8 15.97 6.8 15.2 C 6.8 14.43 7.43 13.8 8.2 13.8 C 8.97 13.8 9.6 14.43 9.6 15.2 Z", 0),
            ("solid", "M 17.2 15.2 C 17.2 15.97 16.57 16.6 15.8 16.6 C 15.03 16.6 14.4 15.97 14.4 15.2 C 14.4 14.43 15.03 13.8 15.8 13.8 C 16.57 13.8 17.2 14.43 17.2 15.2 Z", 0),
            ("solid", "M 10.6 15.4 L 13.4 15.4", 1.4),
            ("hi", "M 8.2 7.4 L 10 7.4", 1.2),
        ]
        case .housing: [
            ("solid", "M 16.4 3.4 L 17.2 3.4 C 17.75 3.4 18.2 3.85 18.2 4.4 L 18.2 7.4 C 18.2 7.95 17.75 8.4 17.2 8.4 L 16.4 8.4 C 15.85 8.4 15.4 7.95 15.4 7.4 L 15.4 4.4 C 15.4 3.85 15.85 3.4 16.4 3.4 Z", 0),
            ("soft", "M 5.5 10 L 18.5 10 C 18.78 10 19 10.22 19 10.5 L 19 18.4 C 19 19.84 17.84 21 16.4 21 L 7.6 21 C 6.16 21 5 19.84 5 18.4 L 5 10.5 C 5 10.22 5.22 10 5.5 10 Z", 0),
            ("solid", "M 10.79 3.84 C 11.54 3.2 12.46 3.2 13.21 3.84 L 20.79 10.36 C 21.54 11 21.39 11.4 20.4 11.4 L 3.6 11.4 C 2.61 11.4 2.46 11 3.21 10.36 Z", 0),
            ("solid", "M 12 17.87 C 11.09 17.09 9.4 15.92 9.4 14.62 C 9.4 13.19 11.22 12.67 12 14.1 C 12.78 12.67 14.6 13.19 14.6 14.62 C 14.6 15.92 12.91 17.09 12 17.87 Z", 0),
            ("hi", "M 7.6 9.2 L 10.2 7", 1.2),
        ]
        case .utilities: [
            ("soft", "M 12 2.6 C 16.3 2.6 19.2 5.8 19.2 9.6 C 19.2 12.4 17.6 14 16.2 15.4 C 15.5 16.1 15.2 16.8 15.2 17.4 L 8.8 17.4 C 8.8 16.8 8.5 16.1 7.8 15.4 C 6.4 14 4.8 12.4 4.8 9.6 C 4.8 5.8 7.7 2.6 12 2.6 Z", 0),
            ("solid", "M 12.75 5.88 C 12.84 5.46 12.74 5.42 12.49 5.77 L 9.41 10.03 C 9.16 10.38 9.27 10.6 9.7 10.6 L 11.3 10.6 C 11.73 10.6 11.94 10.86 11.85 11.28 L 11.25 13.92 C 11.16 14.34 11.26 14.38 11.51 14.03 L 14.59 9.77 C 14.84 9.42 14.73 9.2 14.3 9.2 L 12.7 9.2 C 12.27 9.2 12.06 8.94 12.15 8.52 Z", 0),
            ("solid", "M 9.8 16.6 L 14.2 16.6 C 14.86 16.6 15.4 17.14 15.4 17.8 L 15.4 17.8 C 15.4 18.46 14.86 19 14.2 19 L 9.8 19 C 9.14 19 8.6 18.46 8.6 17.8 L 8.6 17.8 C 8.6 17.14 9.14 16.6 9.8 16.6 Z", 0),
            ("solid", "M 10.9 19.6 L 13.1 19.6 C 13.71 19.6 14.2 20.09 14.2 20.7 L 14.2 20.7 C 14.2 21.31 13.71 21.8 13.1 21.8 L 10.9 21.8 C 10.29 21.8 9.8 21.31 9.8 20.7 L 9.8 20.7 C 9.8 20.09 10.29 19.6 10.9 19.6 Z", 0),
            ("hi", "M 6.4 8 C 6.4 6.91 7.08 5.93 8.11 5.56", 1.3),
        ]
        case .shopping: [
            ("solid", "M 8.4 9 L 8.4 7 C 8.4 4.6 10 3 12 3 C 14 3 15.6 4.6 15.6 7 L 15.6 9", 1.8),
            ("soft", "M 4.44 9.59 C 4.54 8.23 5.44 7.4 6.8 7.4 L 17.2 7.4 C 18.56 7.4 19.46 8.23 19.56 9.59 L 20.24 18.81 C 20.34 20.17 19.56 21 18.2 21 L 5.8 21 C 4.44 21 3.66 20.17 3.76 18.81 Z", 0),
            ("solid", "M 12 17.24 C 10.88 16.28 8.8 14.84 8.8 13.24 C 8.8 11.48 11.04 10.84 12 12.6 C 12.96 10.84 15.2 11.48 15.2 13.24 C 15.2 14.84 13.12 16.28 12 17.24 Z", 0),
            ("solid", "M 9.6 9.6 C 9.6 10.26 9.06 10.8 8.4 10.8 C 7.74 10.8 7.2 10.26 7.2 9.6 C 7.2 8.94 7.74 8.4 8.4 8.4 C 9.06 8.4 9.6 8.94 9.6 9.6 Z", 0),
            ("solid", "M 16.8 9.6 C 16.8 10.26 16.26 10.8 15.6 10.8 C 14.94 10.8 14.4 10.26 14.4 9.6 C 14.4 8.94 14.94 8.4 15.6 8.4 C 16.26 8.4 16.8 8.94 16.8 9.6 Z", 0),
            ("hi", "M 5.8 11 L 5.6 13", 1.2),
        ]
        case .entertainment: [
            ("soft", "M 7 6.6 L 17 6.6 C 20 6.6 21.6 9.4 22 13.4 C 22.4 17.4 21 19.6 19 19.6 C 17.4 19.6 16.4 18 15.4 16.6 L 8.6 16.6 C 7.6 18 6.6 19.6 5 19.6 C 3 19.6 1.6 17.4 2 13.4 C 2.4 9.4 4 6.6 7 6.6 Z", 0),
            ("solid", "M 6.1 11 L 9.5 11 C 10 11 10.4 11.4 10.4 11.9 L 10.4 11.9 C 10.4 12.4 10 12.8 9.5 12.8 L 6.1 12.8 C 5.6 12.8 5.2 12.4 5.2 11.9 L 5.2 11.9 C 5.2 11.4 5.6 11 6.1 11 Z", 0),
            ("solid", "M 7.8 9.3 L 7.8 9.3 C 8.3 9.3 8.7 9.7 8.7 10.2 L 8.7 13.6 C 8.7 14.1 8.3 14.5 7.8 14.5 L 7.8 14.5 C 7.3 14.5 6.9 14.1 6.9 13.6 L 6.9 10.2 C 6.9 9.7 7.3 9.3 7.8 9.3 Z", 0),
            ("solid", "M 16.85 10.4 C 16.85 11.09 16.29 11.65 15.6 11.65 C 14.91 11.65 14.35 11.09 14.35 10.4 C 14.35 9.71 14.91 9.15 15.6 9.15 C 16.29 9.15 16.85 9.71 16.85 10.4 Z", 0),
            ("solid", "M 19.25 12.8 C 19.25 13.49 18.69 14.05 18 14.05 C 17.31 14.05 16.75 13.49 16.75 12.8 C 16.75 12.11 17.31 11.55 18 11.55 C 18.69 11.55 19.25 12.11 19.25 12.8 Z", 0),
            ("solid", "M 16.7 15 C 16.7 15.61 16.21 16.1 15.6 16.1 C 14.99 16.1 14.5 15.61 14.5 15 C 14.5 14.39 14.99 13.9 15.6 13.9 C 16.21 13.9 16.7 14.39 16.7 15 Z", 0),
            ("hi", "M 5.4 8.6 L 7.4 8.4", 1.2),
        ]
        case .medical: [
            ("soft", "M 5.92 8.77 L 9.88 4.81 L 14.69 9.62 L 10.73 13.58 C 9.4 14.91 7.25 14.91 5.92 13.58 L 5.92 13.58 C 4.59 12.25 4.59 10.1 5.92 8.77 Z", 0),
            ("solid", "M 9.31 14.38 L 13.27 10.42 C 14.6 9.09 16.75 9.09 18.08 10.42 L 18.08 10.42 C 19.41 11.75 19.41 13.9 18.08 15.23 L 14.12 19.19 L 9.31 14.38 Z", 0),
            ("hi", "M 6.2 12.6 L 8.4 10.4", 1.3),
            ("solid", "M 16.2 2.4 L 16.2 2.4 C 16.75 2.4 17.2 2.85 17.2 3.4 L 17.2 7.4 C 17.2 7.95 16.75 8.4 16.2 8.4 L 16.2 8.4 C 15.65 8.4 15.2 7.95 15.2 7.4 L 15.2 3.4 C 15.2 2.85 15.65 2.4 16.2 2.4 Z", 0),
            ("solid", "M 14.2 4.4 L 18.2 4.4 C 18.75 4.4 19.2 4.85 19.2 5.4 L 19.2 5.4 C 19.2 5.95 18.75 6.4 18.2 6.4 L 14.2 6.4 C 13.65 6.4 13.2 5.95 13.2 5.4 L 13.2 5.4 C 13.2 4.85 13.65 4.4 14.2 4.4 Z", 0),
        ]
        case .phone: [
            ("soft", "M 7.8 3.4 L 12.6 3.4 C 14.48 3.4 16 4.92 16 6.8 L 16 18 C 16 19.88 14.48 21.4 12.6 21.4 L 7.8 21.4 C 5.92 21.4 4.4 19.88 4.4 18 L 4.4 6.8 C 4.4 4.92 5.92 3.4 7.8 3.4 Z", 0),
            ("solid", "M 9 18 L 11.4 18 C 11.84 18 12.2 18.36 12.2 18.8 L 12.2 18.8 C 12.2 19.24 11.84 19.6 11.4 19.6 L 9 19.6 C 8.56 19.6 8.2 19.24 8.2 18.8 L 8.2 18.8 C 8.2 18.36 8.56 18 9 18 Z", 0),
            ("solid", "M 14.4 2.4 L 19.6 2.4 C 21 2.4 22 3.4 22 4.8 L 22 8.6 C 22 10 21 11 19.6 11 L 17.6 11 L 15.4 13 L 15.4 11 L 14.4 11 C 13 11 12 10 12 8.6 L 12 4.8 C 12 3.4 13 2.4 14.4 2.4 Z", 0),
            ("hi", "M 15.7 6.8 C 15.7 7.3 15.3 7.7 14.8 7.7 C 14.3 7.7 13.9 7.3 13.9 6.8 C 13.9 6.3 14.3 5.9 14.8 5.9 C 15.3 5.9 15.7 6.3 15.7 6.8 Z", 0),
            ("hi", "M 17.9 6.8 C 17.9 7.3 17.5 7.7 17 7.7 C 16.5 7.7 16.1 7.3 16.1 6.8 C 16.1 6.3 16.5 5.9 17 5.9 C 17.5 5.9 17.9 6.3 17.9 6.8 Z", 0),
            ("hi", "M 20.1 6.8 C 20.1 7.3 19.7 7.7 19.2 7.7 C 18.7 7.7 18.3 7.3 18.3 6.8 C 18.3 6.3 18.7 5.9 19.2 5.9 C 19.7 5.9 20.1 6.3 20.1 6.8 Z", 0),
        ]
        case .travel: [
            ("solid", "M 10.6 2.6 L 13.4 2.6 C 14.5 2.6 15.4 3.5 15.4 4.6 L 15.4 6.2 C 15.4 7.3 14.5 8.2 13.4 8.2 L 10.6 8.2 C 9.5 8.2 8.6 7.3 8.6 6.2 L 8.6 4.6 C 8.6 3.5 9.5 2.6 10.6 2.6 Z", 1.7),
            ("solid", "M 9 20.4 C 9 21.17 8.37 21.8 7.6 21.8 C 6.83 21.8 6.2 21.17 6.2 20.4 C 6.2 19.63 6.83 19 7.6 19 C 8.37 19 9 19.63 9 20.4 Z", 0),
            ("solid", "M 17.8 20.4 C 17.8 21.17 17.17 21.8 16.4 21.8 C 15.63 21.8 15 21.17 15 20.4 C 15 19.63 15.63 19 16.4 19 C 17.17 19 17.8 19.63 17.8 20.4 Z", 0),
            ("soft", "M 7.4 6.6 L 16.6 6.6 C 18.59 6.6 20.2 8.21 20.2 10.2 L 20.2 16.4 C 20.2 18.39 18.59 20 16.6 20 L 7.4 20 C 5.41 20 3.8 18.39 3.8 16.4 L 3.8 10.2 C 3.8 8.21 5.41 6.6 7.4 6.6 Z", 0),
            ("solid", "M 7.2 6.6 L 9.4 6.6 L 9.4 20 L 7.2 20 L 7.2 6.6 Z", 0),
            ("solid", "M 14.6 6.6 L 16.8 6.6 L 16.8 20 L 14.6 20 L 14.6 6.6 Z", 0),
            ("hi", "M 5.6 10.2 C 5.6 9.36 6.13 8.61 6.92 8.32", 1.3),
        ]
        case .baby: [
            ("solid", "M 12 1.8 C 13.2 1.8 13.8 2.8 13.8 4 L 13.8 5.4 L 10.2 5.4 L 10.2 4 C 10.2 2.8 10.8 1.8 12 1.8 Z", 0),
            ("solid", "M 9.1 5.2 L 14.9 5.2 C 15.62 5.2 16.2 5.78 16.2 6.5 L 16.2 6.5 C 16.2 7.22 15.62 7.8 14.9 7.8 L 9.1 7.8 C 8.38 7.8 7.8 7.22 7.8 6.5 L 7.8 6.5 C 7.8 5.78 8.38 5.2 9.1 5.2 Z", 0),
            ("soft", "M 10.6 7.4 L 13.4 7.4 C 15.39 7.4 17 9.01 17 11 L 17 18.2 C 17 20.19 15.39 21.8 13.4 21.8 L 10.6 21.8 C 8.61 21.8 7 20.19 7 18.2 L 7 11 C 7 9.01 8.61 7.4 10.6 7.4 Z", 0),
            ("solid", "M 7.6 12 L 10.6 12", 1.4),
            ("solid", "M 7.6 15.2 L 9.8 15.2", 1.4),
            ("solid", "M 7.6 18.4 L 10.6 18.4", 1.4),
            ("solid", "M 14 17.12 C 13.44 16.64 12.4 15.92 12.4 15.12 C 12.4 14.24 13.52 13.92 14 14.8 C 14.48 13.92 15.6 14.24 15.6 15.12 C 15.6 15.92 14.56 16.64 14 17.12 Z", 0),
        ]
        case .other: [
            ("soft", "M 9 3 L 15 3 C 18.31 3 21 5.69 21 9 L 21 15 C 21 18.31 18.31 21 15 21 L 9 21 C 5.69 21 3 18.31 3 15 L 3 9 C 3 5.69 5.69 3 9 3 Z", 0),
            ("solid", "M 9.3 12 C 9.3 12.94 8.54 13.7 7.6 13.7 C 6.66 13.7 5.9 12.94 5.9 12 C 5.9 11.06 6.66 10.3 7.6 10.3 C 8.54 10.3 9.3 11.06 9.3 12 Z", 0),
            ("solid", "M 13.7 12 C 13.7 12.94 12.94 13.7 12 13.7 C 11.06 13.7 10.3 12.94 10.3 12 C 10.3 11.06 11.06 10.3 12 10.3 C 12.94 10.3 13.7 11.06 13.7 12 Z", 0),
            ("solid", "M 18.1 12 C 18.1 12.94 17.34 13.7 16.4 13.7 C 15.46 13.7 14.7 12.94 14.7 12 C 14.7 11.06 15.46 10.3 16.4 10.3 C 17.34 10.3 18.1 11.06 18.1 12 Z", 0),
            ("hi", "M 5.2 7.8 C 5.2 6.71 5.88 5.73 6.91 5.36", 1.3),
        ]
        case .clothing: [
            ("soft", "M 9.9 3.4 C 8.97 3.4 7.89 3.66 7.07 4.09 L 3.93 5.71 C 3.11 6.14 2.83 6.92 3.2 7.78 L 4.18 10.04 C 4.44 10.63 4.97 10.85 5.58 10.61 L 5.62 10.59 C 6.23 10.35 6.6 10.6 6.6 11.25 L 6.6 19.1 C 6.6 20.03 7.17 20.6 8.1 20.6 L 15.9 20.6 C 16.83 20.6 17.4 20.03 17.4 19.1 L 17.4 11.25 C 17.4 10.6 17.77 10.35 18.38 10.59 L 18.42 10.61 C 19.03 10.85 19.56 10.63 19.82 10.04 L 20.8 7.78 C 21.17 6.92 20.89 6.14 20.07 5.71 L 16.93 4.09 C 16.11 3.66 15.03 3.4 14.1 3.4 Z", 0),
            ("solid", "M 8.4 3.4 L 15.6 3.4 C 15.6 5.4 14 6.8 12 6.8 C 10 6.8 8.4 5.4 8.4 3.4 Z", 0),
            ("solid", "M 12 15.68 C 11.16 14.96 9.6 13.88 9.6 12.68 C 9.6 11.36 11.28 10.88 12 12.2 C 12.72 10.88 14.4 11.36 14.4 12.68 C 14.4 13.88 12.84 14.96 12 15.68 Z", 0),
        ]
        case .gift: [
            ("solid", "M 12 7.4 C 10.6 4.2 7.4 3.2 6.6 4.8 C 5.8 6.4 8.4 7.4 12 7.4 Z", 1.6),
            ("solid", "M 12 7.4 C 13.4 4.2 16.6 3.2 17.4 4.8 C 18.2 6.4 15.6 7.4 12 7.4 Z", 1.6),
            ("soft", "M 4.4 11.4 L 19.6 11.4 L 19.6 18.8 C 19.6 20.24 18.44 21.4 17 21.4 L 7 21.4 C 5.56 21.4 4.4 20.24 4.4 18.8 L 4.4 11.4 Z", 0),
            ("solid", "M 4.8 7.4 L 19.2 7.4 C 20.19 7.4 21 8.21 21 9.2 L 21 10.2 C 21 11.19 20.19 12 19.2 12 L 4.8 12 C 3.81 12 3 11.19 3 10.2 L 3 9.2 C 3 8.21 3.81 7.4 4.8 7.4 Z", 0),
            ("solid", "M 10.6 7.4 L 13.4 7.4 L 13.4 21.4 L 10.6 21.4 L 10.6 7.4 Z", 0),
            ("hi", "M 5.2 9.6 L 7.4 9.6", 1.2),
        ]
        case .coffee: [
            ("solid", "M 17.4 11 L 18.4 11 C 20 11 21 12 21 13.4 C 21 14.8 20 15.8 18.4 15.8 L 17 15.8", 1.8),
            ("soft", "M 3.6 9.6 L 18.4 9.6 L 18.4 14.4 C 18.4 18.2 15.4 21 11.6 21 L 10.4 21 C 6.6 21 3.6 18.2 3.6 14.4 Z", 0),
            ("solid", "M 18.4 9.6 C 18.4 10.48 15.09 11.2 11 11.2 C 6.91 11.2 3.6 10.48 3.6 9.6 C 3.6 8.72 6.91 8 11 8 C 15.09 8 18.4 8.72 18.4 9.6 Z", 0),
            ("solid", "M 8.4 2.6 C 7.4 3.8 9.4 4.8 8.4 6.4", 1.4),
            ("solid", "M 12.6 2.6 C 11.6 3.8 13.6 4.8 12.6 6.4", 1.4),
            ("solid", "M 11 16.9 C 10.3 16.3 9 15.4 9 14.4 C 9 13.3 10.4 12.9 11 14 C 11.6 12.9 13 13.3 13 14.4 C 13 15.4 11.7 16.3 11 16.9 Z", 0),
        ]
        case .fuel: [
            ("solid", "M 15.6 9 L 17.6 9 C 18.6 9 19.4 9.8 19.4 10.8 L 19.4 16.6 C 19.4 17.6 20.2 18.2 21 18 L 21 7.4 L 18.8 4.8", 1.6),
            ("soft", "M 6.6 3 L 13 3 C 14.66 3 16 4.34 16 6 L 16 18.4 C 16 20.06 14.66 21.4 13 21.4 L 6.6 21.4 C 4.94 21.4 3.6 20.06 3.6 18.4 L 3.6 6 C 3.6 4.34 4.94 3 6.6 3 Z", 0),
            ("solid", "M 7.6 5.4 L 12 5.4 C 12.88 5.4 13.6 6.12 13.6 7 L 13.6 8.8 C 13.6 9.68 12.88 10.4 12 10.4 L 7.6 10.4 C 6.72 10.4 6 9.68 6 8.8 L 6 7 C 6 6.12 6.72 5.4 7.6 5.4 Z", 0),
            ("solid", "M 3.5 19.4 L 16.1 19.4 C 16.71 19.4 17.2 19.89 17.2 20.5 L 17.2 20.5 C 17.2 21.11 16.71 21.6 16.1 21.6 L 3.5 21.6 C 2.89 21.6 2.4 21.11 2.4 20.5 L 2.4 20.5 C 2.4 19.89 2.89 19.4 3.5 19.4 Z", 0),
            ("solid", "M 9.8 12.4 C 10.8 13.8 11.6 14.8 11.6 15.8 C 11.6 16.8 10.8 17.4 9.8 17.4 C 8.8 17.4 8 16.8 8 15.8 C 8 14.8 8.8 13.8 9.8 12.4 Z", 0),
            ("hi", "M 7.6 7.2 L 9 7.2", 1.2),
        ]
        case .pets: [
            ("solid", "M 7.3 9.78 C 7.73 11.1 7.22 12.44 6.17 12.78 C 5.12 13.12 3.92 12.33 3.5 11.02 C 3.07 9.7 3.58 8.36 4.63 8.02 C 5.68 7.68 6.88 8.47 7.3 9.78 Z", 0),
            ("solid", "M 11.69 5.58 C 11.84 7.01 11.03 8.26 9.87 8.39 C 8.72 8.51 7.66 7.45 7.51 6.02 C 7.36 4.59 8.17 3.34 9.33 3.21 C 10.48 3.09 11.54 4.15 11.69 5.58 Z", 0),
            ("solid", "M 16.49 6.02 C 16.34 7.45 15.28 8.51 14.13 8.39 C 12.97 8.26 12.16 7.01 12.31 5.58 C 12.46 4.15 13.52 3.09 14.67 3.21 C 15.83 3.34 16.64 4.59 16.49 6.02 Z", 0),
            ("solid", "M 20.5 11.02 C 20.08 12.33 18.88 13.12 17.83 12.78 C 16.78 12.44 16.27 11.1 16.7 9.78 C 17.12 8.47 18.32 7.68 19.37 8.02 C 20.42 8.36 20.93 9.7 20.5 11.02 Z", 0),
            ("soft", "M 12 11 C 15 11 18.2 14.4 18.2 17.6 C 18.2 19.6 16.8 20.8 15 20.8 C 13.8 20.8 13 20.2 12 20.2 C 11 20.2 10.2 20.8 9 20.8 C 7.2 20.8 5.8 19.6 5.8 17.6 C 5.8 14.4 9 11 12 11 Z", 0),
            ("solid", "M 12 18.11 C 11.37 17.57 10.2 16.76 10.2 15.86 C 10.2 14.87 11.46 14.51 12 15.5 C 12.54 14.51 13.8 14.87 13.8 15.86 C 13.8 16.76 12.63 17.57 12 18.11 Z", 0),
        ]
        case .education: [
            ("solid", "M 2.4 6.6 L 2.4 18.6 C 6 18 9 18.4 12 20.4 C 15 18.4 18 18 21.6 18.6 L 21.6 6.6 Z", 0),
            ("soft", "M 3.8 4.8 C 6.8 4.4 9.6 5 12 6.8 L 12 18.6 C 9.6 17 6.8 16.4 3.8 16.8 Z", 0),
            ("soft", "M 20.2 4.8 C 17.2 4.4 14.4 5 12 6.8 L 12 18.6 C 14.4 17 17.2 16.4 20.2 16.8 Z", 0),
            ("solid", "M 6 8.6 L 9.6 9.4", 1.2),
            ("solid", "M 6 11.4 L 9.6 12.2", 1.2),
            ("solid", "M 16.6 8.2 C 17.06 10.14 17.06 10.14 19 10.6 C 17.06 11.06 17.06 11.06 16.6 13 C 16.14 11.06 16.14 11.06 14.2 10.6 C 16.14 10.14 16.14 10.14 16.6 8.2 Z", 0),
        ]
        case .beauty: [
            ("solid", "M 12 15.6 L 12 15.6 C 12.77 15.6 13.4 16.23 13.4 17 L 13.4 20.6 C 13.4 21.37 12.77 22 12 22 L 12 22 C 11.23 22 10.6 21.37 10.6 20.6 L 10.6 17 C 10.6 16.23 11.23 15.6 12 15.6 Z", 0),
            ("solid", "M 19.4 9.6 C 19.4 13.69 16.09 17 12 17 C 7.91 17 4.6 13.69 4.6 9.6 C 4.6 5.51 7.91 2.2 12 2.2 C 16.09 2.2 19.4 5.51 19.4 9.6 Z", 0),
            ("soft", "M 17.4 9.6 C 17.4 12.58 14.98 15 12 15 C 9.02 15 6.6 12.58 6.6 9.6 C 6.6 6.62 9.02 4.2 12 4.2 C 14.98 4.2 17.4 6.62 17.4 9.6 Z", 0),
            ("hi", "M 8.45 8.97 C 8.68 7.71 9.56 6.66 10.77 6.22", 1.4),
            ("hi", "M 15.2 10.8 C 15.47 11.93 15.47 11.93 16.6 12.2 C 15.47 12.47 15.47 12.47 15.2 13.6 C 14.93 12.47 14.93 12.47 13.8 12.2 C 14.93 11.93 14.93 11.93 15.2 10.8 Z", 0),
        ]
        case .nails: [
            ("solid", "M 11.4 2 L 12.6 2 C 13.59 2 14.4 2.81 14.4 3.8 L 14.4 8.6 C 14.4 9.59 13.59 10.4 12.6 10.4 L 11.4 10.4 C 10.41 10.4 9.6 9.59 9.6 8.6 L 9.6 3.8 C 9.6 2.81 10.41 2 11.4 2 Z", 0),
            ("solid", "M 9.4 9 L 14.6 9 C 15.15 9 15.6 9.45 15.6 10 L 15.6 10.4 C 15.6 10.95 15.15 11.4 14.6 11.4 L 9.4 11.4 C 8.85 11.4 8.4 10.95 8.4 10.4 L 8.4 10 C 8.4 9.45 8.85 9 9.4 9 Z", 0),
            ("soft", "M 9 11 L 15 11 C 17.6 11 19 13 19 15.6 L 19 17.4 C 19 19.8 17.2 21.4 14.8 21.4 L 9.2 21.4 C 6.8 21.4 5 19.8 5 17.4 L 5 15.6 C 5 13 6.4 11 9 11 Z", 0),
            ("solid", "M 12 18.29 C 11.23 17.63 9.8 16.64 9.8 15.54 C 9.8 14.33 11.34 13.89 12 15.1 C 12.66 13.89 14.2 14.33 14.2 15.54 C 14.2 16.64 12.77 17.63 12 18.29 Z", 0),
            ("hi", "M 7.2 15.2 L 7.2 17.2", 1.3),
            ("hi", "M 11 3.6 L 11 6", 1.1),
        ]
        case .subscription: [
            ("soft", "M 21.4 12 C 21.4 17.19 17.19 21.4 12 21.4 C 6.81 21.4 2.6 17.19 2.6 12 C 2.6 6.81 6.81 2.6 12 2.6 C 17.19 2.6 21.4 6.81 21.4 12 Z", 0),
            ("solid", "M 6.36 9.95 C 7.16 7.76 9.15 6.23 11.48 6.02 C 13.8 5.82 16.03 6.98 17.2 9", 1.8),
            ("solid", "M 16.4 6.66 C 16.52 6.37 16.7 6.36 16.87 6.62 L 18.53 9.18 C 18.7 9.44 18.61 9.61 18.3 9.63 L 15.5 9.77 C 15.19 9.79 15.08 9.63 15.2 9.34 Z", 0),
            ("solid", "M 17.64 14.05 C 16.84 16.24 14.85 17.77 12.52 17.98 C 10.2 18.18 7.97 17.02 6.8 15", 1.8),
            ("solid", "M 7.6 17.34 C 7.48 17.63 7.3 17.64 7.13 17.38 L 5.47 14.82 C 5.3 14.56 5.39 14.39 5.7 14.37 L 8.5 14.23 C 8.81 14.21 8.92 14.37 8.8 14.66 Z", 0),
            ("solid", "M 12 9.4 C 12.49 11.51 12.49 11.51 14.6 12 C 12.49 12.49 12.49 12.49 12 14.6 C 11.51 12.49 11.51 12.49 9.4 12 C 11.51 11.51 11.51 11.51 12 9.4 Z", 0),
        ]
        case .insurance: [
            ("solid", "M 12 11.6 L 12 18.6 C 12 20 13 20.8 14 20.8 C 15 20.8 15.8 20 15.8 19", 1.8),
            ("soft", "M 2.6 12 C 2.6 6.8 6.8 3 12 3 C 17.2 3 21.4 6.8 21.4 12 C 20.4 10.8 19.2 10.8 18.2 12 C 17.2 10.8 15.6 10.8 14.6 12 C 13.8 10.8 12.6 10.6 12 10.6 C 11.4 10.6 10.2 10.8 9.4 12 C 8.4 10.8 6.8 10.8 5.8 12 C 4.8 10.8 3.6 10.8 2.6 12 Z", 0),
            ("solid", "M 12 3 C 9.4 5 8.8 9 9.4 12 C 10.2 10.8 11.4 10.6 12 10.6 C 12.6 10.6 13.8 10.8 14.6 12 C 15.2 9 14.6 5 12 3 Z", 0),
            ("solid", "M 13.1 2.6 C 13.1 3.21 12.61 3.7 12 3.7 C 11.39 3.7 10.9 3.21 10.9 2.6 C 10.9 1.99 11.39 1.5 12 1.5 C 12.61 1.5 13.1 1.99 13.1 2.6 Z", 0),
            ("hi", "M 5.42 9.61 C 5.91 8.26 6.81 7.09 7.98 6.27", 1.2),
        ]
        case .tax: [
            ("soft", "M 5 2.6 L 19 2.6 L 19 21 L 16.7 19.6 L 14.4 21 L 12 19.6 L 9.6 21 L 7.3 19.6 L 5 21 Z", 0),
            ("solid", "M 8 6.6 L 16 6.6", 1.5),
            ("solid", "M 8 10 L 13 10", 1.5),
            ("solid", "M 18.8 15 C 18.8 16.88 17.28 18.4 15.4 18.4 C 13.52 18.4 12 16.88 12 15 C 12 13.12 13.52 11.6 15.4 11.6 C 17.28 11.6 18.8 13.12 18.8 15 Z", 0),
            ("hi", "M 16.4 13.4 C 15 12.8 13.6 13.8 13.6 15 C 13.6 16.2 15 17.2 16.4 16.6", 1.1),
        ]
        case .social: [
            ("soft", "M 12 2.4 L 19.6 5.2 L 19.6 11 C 19.6 16 16.4 19.6 12 21.4 C 7.6 19.6 4.4 16 4.4 11 L 4.4 5.2 Z", 0),
            ("solid", "M 12 15.02 C 10.74 13.94 8.4 12.32 8.4 10.52 C 8.4 8.54 10.92 7.82 12 9.8 C 13.08 7.82 15.6 8.54 15.6 10.52 C 15.6 12.32 13.26 13.94 12 15.02 Z", 0),
            ("hi", "M 7 7.2 L 9.4 6.2", 1.2),
        ]
        case .fee: [
            ("soft", "M 21.4 12 C 21.4 17.19 17.19 21.4 12 21.4 C 6.81 21.4 2.6 17.19 2.6 12 C 2.6 6.81 6.81 2.6 12 2.6 C 17.19 2.6 21.4 6.81 21.4 12 Z", 0),
            ("solid", "M 10.8 8.8 C 10.8 9.9 9.9 10.8 8.8 10.8 C 7.7 10.8 6.8 9.9 6.8 8.8 C 6.8 7.7 7.7 6.8 8.8 6.8 C 9.9 6.8 10.8 7.7 10.8 8.8 Z", 0),
            ("solid", "M 17.2 15.2 C 17.2 16.3 16.3 17.2 15.2 17.2 C 14.1 17.2 13.2 16.3 13.2 15.2 C 13.2 14.1 14.1 13.2 15.2 13.2 C 16.3 13.2 17.2 14.1 17.2 15.2 Z", 0),
            ("solid", "M 15.8 7.6 L 8.2 16.4", 1.9),
        ]
        case .refund: [
            ("soft", "M 21.4 13 C 21.4 17.53 17.73 21.2 13.2 21.2 C 8.67 21.2 5 17.53 5 13 C 5 8.47 8.67 4.8 13.2 4.8 C 17.73 4.8 21.4 8.47 21.4 13 Z", 0),
            ("solid", "M 3.4 9.6 C 4.6 5.6 8.4 3 12.8 3.4", 1.8),
            ("solid", "M 2.2 6.22 C 1.83 6.21 1.75 6.37 2 6.64 L 5.4 10.36 C 5.65 10.63 5.84 10.58 5.91 10.21 L 6.49 6.99 C 6.56 6.62 6.37 6.39 6 6.38 Z", 0),
            ("solid", "M 17.4 13 C 17.4 15.32 15.52 17.2 13.2 17.2 C 10.88 17.2 9 15.32 9 13 C 9 10.68 10.88 8.8 13.2 8.8 C 15.52 8.8 17.4 10.68 17.4 13 Z", 0),
            ("hi", "M 10.84 12.58 C 11.01 11.59 11.79 10.81 12.78 10.64", 1.1),
        ]
        case .salary: [
            ("soft", "M 8.6 7.6 C 5 10 3.4 13.4 3.4 16.2 C 3.4 19.6 6.6 21.4 12 21.4 C 17.4 21.4 20.6 19.6 20.6 16.2 C 20.6 13.4 19 10 15.4 7.6 Z", 0),
            ("solid", "M 8 3 C 9.2 4 10.6 2.6 12 3.6 C 13.4 2.6 14.8 4 16 3 L 15.4 7.6 L 8.6 7.6 Z", 0),
            ("solid", "M 9 6.8 L 15 6.8 C 15.55 6.8 16 7.25 16 7.8 L 16 7.8 C 16 8.35 15.55 8.8 15 8.8 L 9 8.8 C 8.45 8.8 8 8.35 8 7.8 L 8 7.8 C 8 7.25 8.45 6.8 9 6.8 Z", 0),
            ("solid", "M 15.4 15 C 15.4 16.88 13.88 18.4 12 18.4 C 10.12 18.4 8.6 16.88 8.6 15 C 8.6 13.12 10.12 11.6 12 11.6 C 13.88 11.6 15.4 13.12 15.4 15 Z", 0),
            ("hi", "M 12 13.6 C 12.27 14.73 12.27 14.73 13.4 15 C 12.27 15.27 12.27 15.27 12 16.4 C 11.73 15.27 11.73 15.27 10.6 15 C 11.73 14.73 11.73 14.73 12 13.6 Z", 0),
        ]
        case .income: [
            ("soft", "M 17 18.2 C 17 19.64 13.87 20.8 10 20.8 C 6.13 20.8 3 19.64 3 18.2 C 3 16.76 6.13 15.6 10 15.6 C 13.87 15.6 17 16.76 17 18.2 Z", 0),
            ("soft", "M 17 14.6 C 17 16.04 13.87 17.2 10 17.2 C 6.13 17.2 3 16.04 3 14.6 C 3 13.16 6.13 12 10 12 C 13.87 12 17 13.16 17 14.6 Z", 0),
            ("solid", "M 17 11 C 17 12.44 13.87 13.6 10 13.6 C 6.13 13.6 3 12.44 3 11 C 3 9.56 6.13 8.4 10 8.4 C 13.87 8.4 17 9.56 17 11 Z", 0),
            ("hi", "M 5.56 10.61 C 5.91 10.18 6.82 9.83 8.06 9.64", 1.1),
            ("solid", "M 21.8 6 C 21.8 8.1 20.1 9.8 18 9.8 C 15.9 9.8 14.2 8.1 14.2 6 C 14.2 3.9 15.9 2.2 18 2.2 C 20.1 2.2 21.8 3.9 21.8 6 Z", 0),
            ("hi", "M 18 4.4 L 18 7.6", 1.4),
            ("hi", "M 16.6 6.4 L 18 7.8 L 19.4 6.4", 1.4),
        ]
        case .revenue: [
            ("soft", "M 5.2 10 L 18.8 10 C 20.24 10 21.4 11.16 21.4 12.6 L 21.4 18.8 C 21.4 20.24 20.24 21.4 18.8 21.4 L 5.2 21.4 C 3.76 21.4 2.6 20.24 2.6 18.8 L 2.6 12.6 C 2.6 11.16 3.76 10 5.2 10 Z", 0),
            ("solid", "M 6.6 3 L 12.6 3 C 13.48 3 14.2 3.72 14.2 4.6 L 14.2 7 C 14.2 7.88 13.48 8.6 12.6 8.6 L 6.6 8.6 C 5.72 8.6 5 7.88 5 7 L 5 4.6 C 5 3.72 5.72 3 6.6 3 Z", 0),
            ("solid", "M 8.4 8 L 10.8 8 L 10.8 11 L 8.4 11 L 8.4 8 Z", 0),
            ("hi", "M 7.8 14.2 C 7.8 14.75 7.35 15.2 6.8 15.2 C 6.25 15.2 5.8 14.75 5.8 14.2 C 5.8 13.65 6.25 13.2 6.8 13.2 C 7.35 13.2 7.8 13.65 7.8 14.2 Z", 0),
            ("hi", "M 11 14.2 C 11 14.75 10.55 15.2 10 15.2 C 9.45 15.2 9 14.75 9 14.2 C 9 13.65 9.45 13.2 10 13.2 C 10.55 13.2 11 13.65 11 14.2 Z", 0),
            ("hi", "M 14.2 14.2 C 14.2 14.75 13.75 15.2 13.2 15.2 C 12.65 15.2 12.2 14.75 12.2 14.2 C 12.2 13.65 12.65 13.2 13.2 13.2 C 13.75 13.2 14.2 13.65 14.2 14.2 Z", 0),
            ("solid", "M 6.5 17.2 L 13.1 17.2 C 13.6 17.2 14 17.6 14 18.1 L 14 18.1 C 14 18.6 13.6 19 13.1 19 L 6.5 19 C 6 19 5.6 18.6 5.6 18.1 L 5.6 18.1 C 5.6 17.6 6 17.2 6.5 17.2 Z", 0),
            ("solid", "M 21.6 6.2 C 21.6 7.97 20.17 9.4 18.4 9.4 C 16.63 9.4 15.2 7.97 15.2 6.2 C 15.2 4.43 16.63 3 18.4 3 C 20.17 3 21.6 4.43 21.6 6.2 Z", 0),
            ("hi", "M 18.4 4.9 C 18.65 5.95 18.65 5.95 19.7 6.2 C 18.65 6.45 18.65 6.45 18.4 7.5 C 18.15 6.45 18.15 6.45 17.1 6.2 C 18.15 5.95 18.15 5.95 18.4 4.9 Z", 0),
        ]
        case .shoprent: [
            ("soft", "M 4 9 L 20 9 L 20 19 C 20 20.33 18.93 21.4 17.6 21.4 L 6.4 21.4 C 5.07 21.4 4 20.33 4 19 L 4 9 Z", 0),
            ("solid", "M 3 4 L 21 4 L 22 9 C 22 10.6 20.6 11.6 19.4 11.6 C 18.2 11.6 17 10.8 16.7 9.6 C 16.4 10.8 15.2 11.6 14 11.6 C 12.8 11.6 12.3 11 12 10 C 11.7 11 11.2 11.6 10 11.6 C 8.8 11.6 7.6 10.8 7.3 9.6 C 7 10.8 5.8 11.6 4.6 11.6 C 3.4 11.6 2 10.6 2 9 Z", 0),
            ("hi", "M 7 5.8 L 7.6 9", 1.3),
            ("hi", "M 12 5.8 L 12 9", 1.3),
            ("hi", "M 17 5.8 L 16.4 9", 1.3),
            ("solid", "M 14.8 14 L 16 14 C 16.88 14 17.6 14.72 17.6 15.6 L 17.6 21.4 L 13.2 21.4 L 13.2 15.6 C 13.2 14.72 13.92 14 14.8 14 Z", 0),
            ("solid", "M 8.6 17.71 C 7.97 17.17 6.8 16.36 6.8 15.46 C 6.8 14.47 8.06 14.11 8.6 15.1 C 9.14 14.11 10.4 14.47 10.4 15.46 C 10.4 16.36 9.23 17.17 8.6 17.71 Z", 0),
        ]
        case .supplies: [
            ("soft", "M 10.56 3.3 C 11.45 2.87 12.55 2.87 13.44 3.3 L 19.56 6.3 C 20.45 6.73 21 7.61 21 8.6 L 21 15.4 C 21 16.39 20.45 17.27 19.56 17.7 L 13.44 20.7 C 12.55 21.13 11.45 21.13 10.56 20.7 L 4.44 17.7 C 3.55 17.27 3 16.39 3 15.4 L 3 8.6 C 3 7.61 3.55 6.73 4.44 6.3 Z", 0),
            ("solid", "M 12 12.8 C 12 11.93 12.48 11.17 13.26 10.79 L 19.74 7.61 C 20.52 7.23 21 7.53 21 8.4 L 21 15.6 C 21 16.47 20.52 17.23 19.74 17.61 L 13.26 20.79 C 12.48 21.17 12 20.87 12 20 Z", 0),
            ("solid", "M 7.4 4.8 L 16.4 9.2 L 16.4 12.6", 1.6),
            ("hi", "M 16.6 15.93 C 16.11 15.51 15.2 14.88 15.2 14.18 C 15.2 13.41 16.18 13.13 16.6 13.9 C 17.02 13.13 18 13.41 18 14.18 C 18 14.88 17.09 15.51 16.6 15.93 Z", 0),
        ]
        case .equipment: [
            ("solid", "M 10 3.2 L 14 3.2 C 14.99 3.2 15.8 4.01 15.8 5 L 15.8 6.4 C 15.8 7.39 14.99 8.2 14 8.2 L 10 8.2 C 9.01 8.2 8.2 7.39 8.2 6.4 L 8.2 5 C 8.2 4.01 9.01 3.2 10 3.2 Z", 1.7),
            ("soft", "M 5.8 7 L 18.2 7 C 19.86 7 21.2 8.34 21.2 10 L 21.2 17.6 C 21.2 19.26 19.86 20.6 18.2 20.6 L 5.8 20.6 C 4.14 20.6 2.8 19.26 2.8 17.6 L 2.8 10 C 2.8 8.34 4.14 7 5.8 7 Z", 0),
            ("solid", "M 2.8 11.4 L 21.2 11.4 L 21.2 13.8 L 2.8 13.8 L 2.8 11.4 Z", 0),
            ("solid", "M 11.4 10 L 12.6 10 C 13.37 10 14 10.63 14 11.4 L 14 13.8 C 14 14.57 13.37 15.2 12.6 15.2 L 11.4 15.2 C 10.63 15.2 10 14.57 10 13.8 L 10 11.4 C 10 10.63 10.63 10 11.4 10 Z", 0),
            ("hi", "M 4.4 10.4 C 4.4 9.64 4.87 8.97 5.58 8.71", 1.3),
        ]
        case .staff: [
            ("soft", "M 2.6 20.6 C 2.6 16.4 5.6 13.6 10 13.6 C 14.4 13.6 17.4 16.4 17.4 20.6 Z", 0),
            ("solid", "M 14.4 8 C 14.4 10.43 12.43 12.4 10 12.4 C 7.57 12.4 5.6 10.43 5.6 8 C 5.6 5.57 7.57 3.6 10 3.6 C 12.43 3.6 14.4 5.57 14.4 8 Z", 0),
            ("hi", "M 7.49 7.33 C 7.71 6.51 8.31 5.85 9.11 5.56", 1.2),
            ("solid", "M 21.8 16.4 C 21.8 18.5 20.1 20.2 18 20.2 C 15.9 20.2 14.2 18.5 14.2 16.4 C 14.2 14.3 15.9 12.6 18 12.6 C 20.1 12.6 21.8 14.3 21.8 16.4 Z", 0),
            ("hi", "M 18 14.9 C 18.29 16.11 18.29 16.11 19.5 16.4 C 18.29 16.68 18.29 16.68 18 17.9 C 17.71 16.68 17.71 16.68 16.5 16.4 C 17.71 16.11 17.71 16.11 18 14.9 Z", 0),
        ]
        case .marketing: [
            ("solid", "M 18.2 8 C 19.6 9 20.4 10.4 20.4 12 C 20.4 13.6 19.6 15 18.2 16", 1.6),
            ("solid", "M 20.4 5.6 C 22.2 7.2 23 9.6 23 12 C 23 14.4 22.2 16.8 20.4 18.4", 1.4),
            ("solid", "M 6.6 14.12 L 7.39 13.98 C 8.26 13.83 9.09 14.41 9.24 15.28 L 9.9 19.02 C 10.05 19.89 9.47 20.72 8.6 20.88 L 7.81 21.02 C 6.94 21.17 6.11 20.59 5.96 19.72 L 5.3 15.98 C 5.15 15.11 5.73 14.28 6.6 14.12 Z", 0),
            ("soft", "M 3.8 9.2 L 14.6 4.2 C 15.6 3.8 16.6 4.4 16.6 5.6 L 16.6 18.4 C 16.6 19.6 15.6 20.2 14.6 19.8 L 3.8 14.8 Z", 0),
            ("solid", "M 4 8.6 L 4.6 8.6 C 5.7 8.6 6.6 9.5 6.6 10.6 L 6.6 13.4 C 6.6 14.5 5.7 15.4 4.6 15.4 L 4 15.4 C 2.9 15.4 2 14.5 2 13.4 L 2 10.6 C 2 9.5 2.9 8.6 4 8.6 Z", 0),
            ("hi", "M 9 7.6 L 12.4 6", 1.2),
        ]
        case .topup: [
            ("soft", "M 5.4 5 L 16.4 5 C 18.06 5 19.4 6.34 19.4 8 L 19.4 14 C 19.4 15.66 18.06 17 16.4 17 L 5.4 17 C 3.74 17 2.4 15.66 2.4 14 L 2.4 8 C 2.4 6.34 3.74 5 5.4 5 Z", 0),
            ("solid", "M 2.4 8 L 19.4 8 L 19.4 10.6 L 2.4 10.6 L 2.4 8 Z", 0),
            ("solid", "M 5.4 14 L 9 14", 1.4),
            ("solid", "M 22.6 17 C 22.6 19.54 20.54 21.6 18 21.6 C 15.46 21.6 13.4 19.54 13.4 17 C 13.4 14.46 15.46 12.4 18 12.4 C 20.54 12.4 22.6 14.46 22.6 17 Z", 0),
            ("hi", "M 18 15 L 18 19", 1.6),
            ("hi", "M 16 17 L 20 17", 1.6),
        ]
        case .transfer: [
            ("soft", "M 19 15.6 L 6 15.6", 2.4),
            ("soft", "M 8.8 12.6 C 8.8 11.98 8.49 11.83 8 12.2 L 4.2 15 C 3.71 15.37 3.71 15.83 4.2 16.2 L 8 19 C 8.49 19.37 8.8 19.22 8.8 18.6 Z", 0),
            ("solid", "M 5 8.4 L 18 8.4", 2.4),
            ("solid", "M 15.2 5.4 C 15.2 4.78 15.51 4.63 16 5 L 19.8 7.8 C 20.29 8.17 20.29 8.63 19.8 9 L 16 11.8 C 15.51 12.17 15.2 12.02 15.2 11.4 Z", 0),
        ]
        case .withdraw: [
            ("soft", "M 6 6 L 14.6 6 C 16.48 6 18 7.52 18 9.4 L 18 17.2 C 18 19.08 16.48 20.6 14.6 20.6 L 6 20.6 C 4.12 20.6 2.6 19.08 2.6 17.2 L 2.6 9.4 C 2.6 7.52 4.12 6 6 6 Z", 0),
            ("solid", "M 2.6 9.2 C 2.6 7.4 4 6 5.8 6 L 14.4 6 L 12.4 3.6 C 12 3.2 11.4 3 10.8 3.2 L 4.6 5.2", 0),
            ("solid", "M 15.4 13.4 C 15.4 14.17 14.77 14.8 14 14.8 C 13.23 14.8 12.6 14.17 12.6 13.4 C 12.6 12.63 13.23 12 14 12 C 14.77 12 15.4 12.63 15.4 13.4 Z", 0),
            ("solid", "M 14.6 13.4 L 21.6 13.4", 2),
            ("solid", "M 19 10.6 C 19 10.1 19.23 10 19.59 10.34 L 22.41 12.86 C 22.77 13.2 22.77 13.6 22.41 13.94 L 19.59 16.46 C 19.23 16.8 19 16.7 19 16.2 Z", 0),
        ]
        case .savings: [
            ("solid", "M 20.2 4 C 20.2 5.44 19.04 6.6 17.6 6.6 C 16.16 6.6 15 5.44 15 4 C 15 2.56 16.16 1.4 17.6 1.4 C 19.04 1.4 20.2 2.56 20.2 4 Z", 0),
            ("soft", "M 11.4 6.2 C 16.6 6.2 20 9.4 20 13.4 C 20 15.8 18.8 17.6 17.2 18.6 L 17.2 20.6 C 17.2 21.2 16.8 21.6 16.2 21.6 L 14.6 21.6 C 14 21.6 13.6 21.2 13.6 20.6 L 13.6 19.8 C 12.8 20 12 20 11.2 20 C 10.4 20 9.6 20 8.8 19.8 L 8.8 20.6 C 8.8 21.2 8.4 21.6 7.8 21.6 L 6.2 21.6 C 5.6 21.6 5.2 21.2 5.2 20.6 L 5.2 18.2 C 4.4 17.6 3.8 16.8 3.4 16 L 2.6 16 C 2 16 1.6 15.6 1.6 15 L 1.6 12.4 C 1.6 11.8 2 11.4 2.6 11.4 L 3.4 11.4 C 4 9.6 5 8.4 6.2 7.6 L 5.4 4.6 C 5.3 4.2 5.7 3.9 6.1 4 L 9.2 5.6 C 9.9 6.2 10.6 6.2 11.4 6.2 Z", 0),
            ("solid", "M 10.2 8.6 L 13.2 8.6 C 13.64 8.6 14 8.96 14 9.4 L 14 9.4 C 14 9.84 13.64 10.2 13.2 10.2 L 10.2 10.2 C 9.76 10.2 9.4 9.84 9.4 9.4 L 9.4 9.4 C 9.4 8.96 9.76 8.6 10.2 8.6 Z", 0),
            ("solid", "M 16.4 12 C 16.4 12.55 15.95 13 15.4 13 C 14.85 13 14.4 12.55 14.4 12 C 14.4 11.45 14.85 11 15.4 11 C 15.95 11 16.4 11.45 16.4 12 Z", 0),
            ("solid", "M 20 12.6 C 21.4 12.2 22.4 12.8 22.2 14 C 22 15 20.8 14.6 21 13.6", 0),
            ("hi", "M 17.6 2.8 L 17.6 5.2", 1),
        ]
        case .invest: [
            ("soft", "M 20.4 19 C 20.4 20.55 16.64 21.8 12 21.8 C 7.36 21.8 3.6 20.55 3.6 19 C 3.6 17.45 7.36 16.2 12 16.2 C 16.64 16.2 20.4 17.45 20.4 19 Z", 0),
            ("solid", "M 20.4 16.6 C 20.4 18.15 16.64 19.4 12 19.4 C 7.36 19.4 3.6 18.15 3.6 16.6 C 3.6 15.05 7.36 13.8 12 13.8 C 16.64 13.8 20.4 15.05 20.4 16.6 Z", 0),
            ("solid", "M 12 15.4 L 12 8.6", 1.8),
            ("solid", "M 12 10.4 C 12 6.6 9.4 4.6 5.4 4.8 C 5.4 8.6 8 10.6 12 10.4 Z", 0),
            ("soft", "M 12 8.8 C 12 5 14.6 3 18.6 3.2 C 18.6 7 16 9 12 8.8 Z", 0),
            ("hi", "M 6.93 16.05 C 7.36 15.7 8.2 15.4 9.3 15.21", 1.1),
        ]
        case .loan: [
            ("soft", "M 5.6 3.4 L 13.8 3.4 C 15.24 3.4 16.4 4.56 16.4 6 L 16.4 18 C 16.4 19.44 15.24 20.6 13.8 20.6 L 5.6 20.6 C 4.16 20.6 3 19.44 3 18 L 3 6 C 3 4.56 4.16 3.4 5.6 3.4 Z", 0),
            ("solid", "M 6.2 8 L 13.2 8", 1.5),
            ("solid", "M 6.2 11.4 L 11 11.4", 1.5),
            ("solid", "M 21.6 16 C 21.6 18.76 19.36 21 16.6 21 C 13.84 21 11.6 18.76 11.6 16 C 11.6 13.24 13.84 11 16.6 11 C 19.36 11 21.6 13.24 21.6 16 Z", 0),
            ("hi", "M 14.4 14.6 L 18.8 14.6", 1.3),
            ("hi", "M 18.8 17.4 L 14.4 17.4", 1.3),
            ("hi", "M 17.4 13.2 L 18.8 14.6 L 17.4 16", 1.1),
        ]
        case .repay: [
            ("soft", "M 5.6 3.4 L 13.8 3.4 C 15.24 3.4 16.4 4.56 16.4 6 L 16.4 18 C 16.4 19.44 15.24 20.6 13.8 20.6 L 5.6 20.6 C 4.16 20.6 3 19.44 3 18 L 3 6 C 3 4.56 4.16 3.4 5.6 3.4 Z", 0),
            ("solid", "M 6.2 8 L 13.2 8", 1.5),
            ("solid", "M 6.2 11.4 L 11 11.4", 1.5),
            ("solid", "M 21.6 16 C 21.6 18.76 19.36 21 16.6 21 C 13.84 21 11.6 18.76 11.6 16 C 11.6 13.24 13.84 11 16.6 11 C 19.36 11 21.6 13.24 21.6 16 Z", 0),
            ("hi", "M 14.4 16.2 L 16 17.8 L 19 14.4", 1.6),
        ]
        case .sport: [
            ("soft", "M 8.6 10.8 L 15.4 10.8 C 16.06 10.8 16.6 11.34 16.6 12 L 16.6 12 C 16.6 12.66 16.06 13.2 15.4 13.2 L 8.6 13.2 C 7.94 13.2 7.4 12.66 7.4 12 L 7.4 12 C 7.4 11.34 7.94 10.8 8.6 10.8 Z", 0),
            ("solid", "M 5.2 6.2 L 5.4 6.2 C 6.62 6.2 7.6 7.18 7.6 8.4 L 7.6 15.6 C 7.6 16.82 6.62 17.8 5.4 17.8 L 5.2 17.8 C 3.98 17.8 3 16.82 3 15.6 L 3 8.4 C 3 7.18 3.98 6.2 5.2 6.2 Z", 0),
            ("solid", "M 18.6 6.2 L 18.8 6.2 C 20.02 6.2 21 7.18 21 8.4 L 21 15.6 C 21 16.82 20.02 17.8 18.8 17.8 L 18.6 17.8 C 17.38 17.8 16.4 16.82 16.4 15.6 L 16.4 8.4 C 16.4 7.18 17.38 6.2 18.6 6.2 Z", 0),
            ("soft", "M 2 9 L 2.2 9 C 2.86 9 3.4 9.54 3.4 10.2 L 3.4 13.8 C 3.4 14.46 2.86 15 2.2 15 L 2 15 C 1.34 15 0.8 14.46 0.8 13.8 L 0.8 10.2 C 0.8 9.54 1.34 9 2 9 Z", 0),
            ("soft", "M 21.8 9 L 22 9 C 22.66 9 23.2 9.54 23.2 10.2 L 23.2 13.8 C 23.2 14.46 22.66 15 22 15 L 21.8 15 C 21.14 15 20.6 14.46 20.6 13.8 L 20.6 10.2 C 20.6 9.54 21.14 9 21.8 9 Z", 0),
            ("hi", "M 4.6 8.4 L 4.6 10.4", 1.1),
            ("hi", "M 18 8.4 L 18 10.4", 1.1),
        ]
        case .home: [
            ("soft", "M 7.6 6 L 16.4 6 C 18.06 6 19.4 7.34 19.4 9 L 19.4 12.4 C 19.4 14.06 18.06 15.4 16.4 15.4 L 7.6 15.4 C 5.94 15.4 4.6 14.06 4.6 12.4 L 4.6 9 C 4.6 7.34 5.94 6 7.6 6 Z", 0),
            ("solid", "M 2 11.4 C 2 10 3 9 4.4 9 C 5.8 9 6.8 10 6.8 11.4 L 6.8 14 L 17.2 14 L 17.2 11.4 C 17.2 10 18.2 9 19.6 9 C 21 9 22 10 22 11.4 L 22 17.6 C 22 18.6 21.2 19.4 20.2 19.4 L 3.8 19.4 C 2.8 19.4 2 18.6 2 17.6 Z", 0),
            ("solid", "M 5 19 L 5.4 19 C 5.84 19 6.2 19.36 6.2 19.8 L 6.2 20.8 C 6.2 21.24 5.84 21.6 5.4 21.6 L 5 21.6 C 4.56 21.6 4.2 21.24 4.2 20.8 L 4.2 19.8 C 4.2 19.36 4.56 19 5 19 Z", 0),
            ("solid", "M 18.6 19 L 19 19 C 19.44 19 19.8 19.36 19.8 19.8 L 19.8 20.8 C 19.8 21.24 19.44 21.6 19 21.6 L 18.6 21.6 C 18.16 21.6 17.8 21.24 17.8 20.8 L 17.8 19.8 C 17.8 19.36 18.16 19 18.6 19 Z", 0),
            ("hi", "M 12 11.92 C 11.44 11.44 10.4 10.72 10.4 9.92 C 10.4 9.04 11.52 8.72 12 9.6 C 12.48 8.72 13.6 9.04 13.6 9.92 C 13.6 10.72 12.56 11.44 12 11.92 Z", 0),
        ]
        case .snacks: [
            ("solid", "M 5.29 12.71 C 5.73 12.27 5.73 11.73 5.29 11.29 L 2.91 8.91 C 2.47 8.47 2.2 8.58 2.2 9.2 L 2.2 14.8 C 2.2 15.42 2.47 15.53 2.91 15.09 Z", 0),
            ("solid", "M 18.71 12.71 C 18.27 12.27 18.27 11.73 18.71 11.29 L 21.09 8.91 C 21.53 8.47 21.8 8.58 21.8 9.2 L 21.8 14.8 C 21.8 15.42 21.53 15.53 21.09 15.09 Z", 0),
            ("soft", "M 18.8 12 C 18.8 14.98 15.76 17.4 12 17.4 C 8.24 17.4 5.2 14.98 5.2 12 C 5.2 9.02 8.24 6.6 12 6.6 C 15.76 6.6 18.8 9.02 18.8 12 Z", 0),
            ("solid", "M 8.4 8 C 10 10.6 10 13.4 8.4 16", 1.6),
            ("solid", "M 15.6 8 C 14 10.6 14 13.4 15.6 16", 1.6),
            ("hi", "M 8.62 11.11 C 8.98 10.39 9.77 9.82 10.77 9.56", 1.2),
        ]
        case .digital: [
            ("soft", "M 6.4 4 L 17.6 4 C 18.93 4 20 5.07 20 6.4 L 20 13.2 C 20 14.53 18.93 15.6 17.6 15.6 L 6.4 15.6 C 5.07 15.6 4 14.53 4 13.2 L 4 6.4 C 4 5.07 5.07 4 6.4 4 Z", 0),
            ("solid", "M 7.4 6.2 L 16.6 6.2 C 17.26 6.2 17.8 6.74 17.8 7.4 L 17.8 12.2 C 17.8 12.86 17.26 13.4 16.6 13.4 L 7.4 13.4 C 6.74 13.4 6.2 12.86 6.2 12.2 L 6.2 7.4 C 6.2 6.74 6.74 6.2 7.4 6.2 Z", 0),
            ("solid", "M 2 16.8 L 22 16.8 L 22 17.6 C 22 19 21 20 19.6 20 L 4.4 20 C 3 20 2 19 2 17.6 Z", 0),
            ("hi", "M 14.6 8 C 14.9 9.3 14.9 9.3 16.2 9.6 C 14.9 9.9 14.9 9.9 14.6 11.2 C 14.3 9.9 14.3 9.9 13 9.6 C 14.3 9.3 14.3 9.3 14.6 8 Z", 0),
            ("hi", "M 8 8 L 9.6 8", 1.1),
        ]
        case .uncategorized: [
            ("soft", "M 12 3 C 17.2 3 21 6.6 21 11 C 21 15.4 17.2 19 12 19 C 11 19 10 18.8 9.2 18.6 L 5 21 L 5.6 16.8 C 4 15.4 3 13.4 3 11 C 3 6.6 6.8 3 12 3 Z", 0),
            ("solid", "M 9.8 9 C 9.8 7.6 10.8 6.8 12 6.8 C 13.2 6.8 14.2 7.6 14.2 8.8 C 14.2 10.6 12 10.6 12 12.4", 1.8),
            ("solid", "M 13.15 15.2 C 13.15 15.84 12.64 16.35 12 16.35 C 11.36 16.35 10.85 15.84 10.85 15.2 C 10.85 14.56 11.36 14.05 12 14.05 C 12.64 14.05 13.15 14.56 13.15 15.2 Z", 0),
        ]
        case .bank: [
            ("soft", "M 5.2 10 L 6.8 10 C 7.13 10 7.4 10.27 7.4 10.6 L 7.4 17.4 C 7.4 17.73 7.13 18 6.8 18 L 5.2 18 C 4.87 18 4.6 17.73 4.6 17.4 L 4.6 10.6 C 4.6 10.27 4.87 10 5.2 10 Z", 0),
            ("soft", "M 11.2 10 L 12.8 10 C 13.13 10 13.4 10.27 13.4 10.6 L 13.4 17.4 C 13.4 17.73 13.13 18 12.8 18 L 11.2 18 C 10.87 18 10.6 17.73 10.6 17.4 L 10.6 10.6 C 10.6 10.27 10.87 10 11.2 10 Z", 0),
            ("soft", "M 17.2 10 L 18.8 10 C 19.13 10 19.4 10.27 19.4 10.6 L 19.4 17.4 C 19.4 17.73 19.13 18 18.8 18 L 17.2 18 C 16.87 18 16.6 17.73 16.6 17.4 L 16.6 10.6 C 16.6 10.27 16.87 10 17.2 10 Z", 0),
            ("solid", "M 10.96 3 C 11.61 2.63 12.39 2.63 13.04 3 L 20.84 7.56 C 21.31 7.83 21.6 8.33 21.6 8.88 L 21.6 8.92 C 21.6 9.47 21.27 9.8 20.72 9.8 L 3.28 9.8 C 2.73 9.8 2.4 9.47 2.4 8.92 L 2.4 8.88 C 2.4 8.33 2.69 7.83 3.16 7.56 Z", 0),
            ("solid", "M 3.8 18.4 L 20.2 18.4 C 20.97 18.4 21.6 19.03 21.6 19.8 L 21.6 20 C 21.6 20.77 20.97 21.4 20.2 21.4 L 3.8 21.4 C 3.03 21.4 2.4 20.77 2.4 20 L 2.4 19.8 C 2.4 19.03 3.03 18.4 3.8 18.4 Z", 0),
            ("hi", "M 13.3 6.6 C 13.3 7.32 12.72 7.9 12 7.9 C 11.28 7.9 10.7 7.32 10.7 6.6 C 10.7 5.88 11.28 5.3 12 5.3 C 12.72 5.3 13.3 5.88 13.3 6.6 Z", 0),
        ]
        case .credit: [
            ("soft", "M 5.2 4.6 L 18.8 4.6 C 20.57 4.6 22 6.03 22 7.8 L 22 16.2 C 22 17.97 20.57 19.4 18.8 19.4 L 5.2 19.4 C 3.43 19.4 2 17.97 2 16.2 L 2 7.8 C 2 6.03 3.43 4.6 5.2 4.6 Z", 0),
            ("solid", "M 2 8 L 22 8 L 22 11 L 2 11 L 2 8 Z", 0),
            ("solid", "M 5.8 13.4 L 8.4 13.4 C 8.95 13.4 9.4 13.85 9.4 14.4 L 9.4 15.6 C 9.4 16.15 8.95 16.6 8.4 16.6 L 5.8 16.6 C 5.25 16.6 4.8 16.15 4.8 15.6 L 4.8 14.4 C 4.8 13.85 5.25 13.4 5.8 13.4 Z", 0),
            ("solid", "M 12.6 15 L 18.4 15", 1.5),
            ("hi", "M 3.8 7.4 C 3.8 6.81 4.17 6.29 4.72 6.08", 1.3),
        ]
        case .cash: [
            ("soft", "M 3.69 4.9 L 15.78 3.2 C 17.09 3.02 18.3 3.93 18.49 5.25 L 19.35 11.39 C 19.53 12.7 18.62 13.91 17.31 14.1 L 5.22 15.8 C 3.91 15.98 2.7 15.07 2.51 13.75 L 1.65 7.61 C 1.47 6.3 2.38 5.09 3.69 4.9 Z", 0),
            ("solid", "M 7 8.6 L 19.6 8.6 C 20.93 8.6 22 9.67 22 11 L 22 17.6 C 22 18.93 20.93 20 19.6 20 L 7 20 C 5.67 20 4.6 18.93 4.6 17.6 L 4.6 11 C 4.6 9.67 5.67 8.6 7 8.6 Z", 0),
            ("hi", "M 15.9 14.3 C 15.9 15.74 14.74 16.9 13.3 16.9 C 11.86 16.9 10.7 15.74 10.7 14.3 C 10.7 12.86 11.86 11.7 13.3 11.7 C 14.74 11.7 15.9 12.86 15.9 14.3 Z", 0),
            ("solid", "M 14.4 14.3 C 14.4 14.91 13.91 15.4 13.3 15.4 C 12.69 15.4 12.2 14.91 12.2 14.3 C 12.2 13.69 12.69 13.2 13.3 13.2 C 13.91 13.2 14.4 13.69 14.4 14.3 Z", 0),
            ("hi", "M 8.3 11.4 C 8.3 11.9 7.9 12.3 7.4 12.3 C 6.9 12.3 6.5 11.9 6.5 11.4 C 6.5 10.9 6.9 10.5 7.4 10.5 C 7.9 10.5 8.3 10.9 8.3 11.4 Z", 0),
            ("hi", "M 20.1 17.2 C 20.1 17.7 19.7 18.1 19.2 18.1 C 18.7 18.1 18.3 17.7 18.3 17.2 C 18.3 16.7 18.7 16.3 19.2 16.3 C 19.7 16.3 20.1 16.7 20.1 17.2 Z", 0),
        ]
        case .wallet: [
            ("soft", "M 4.52 5.2 L 15.66 4.03 C 16.97 3.89 18.15 4.85 18.29 6.17 L 18.42 7.36 C 18.56 8.68 17.6 9.86 16.28 10 L 5.14 11.17 C 3.83 11.31 2.65 10.35 2.51 9.03 L 2.38 7.84 C 2.24 6.52 3.2 5.34 4.52 5.2 Z", 0),
            ("solid", "M 5.8 7.6 L 18.2 7.6 C 20.08 7.6 21.6 9.12 21.6 11 L 21.6 17.4 C 21.6 19.28 20.08 20.8 18.2 20.8 L 5.8 20.8 C 3.92 20.8 2.4 19.28 2.4 17.4 L 2.4 11 C 2.4 9.12 3.92 7.6 5.8 7.6 Z", 0),
            ("soft", "M 16.4 11.6 L 20 11.6 C 21.33 11.6 22.4 12.67 22.4 14 L 22.4 14.8 C 22.4 16.13 21.33 17.2 20 17.2 L 16.4 17.2 C 15.07 17.2 14 16.13 14 14.8 L 14 14 C 14 12.67 15.07 11.6 16.4 11.6 Z", 0),
            ("hi", "M 18.4 14.4 C 18.4 15.06 17.86 15.6 17.2 15.6 C 16.54 15.6 16 15.06 16 14.4 C 16 13.74 16.54 13.2 17.2 13.2 C 17.86 13.2 18.4 13.74 18.4 14.4 Z", 0),
            ("hi", "M 4.6 10.4 L 7.6 10.4", 1.2),
        ]
        case .stash: [
            ("solid", "M 7.6 2.6 L 16.4 2.6 C 17.28 2.6 18 3.32 18 4.2 L 18 4.6 C 18 5.48 17.28 6.2 16.4 6.2 L 7.6 6.2 C 6.72 6.2 6 5.48 6 4.6 L 6 4.2 C 6 3.32 6.72 2.6 7.6 2.6 Z", 0),
            ("soft", "M 7.4 6 L 16.6 6 C 19 7.4 20.4 9.8 20.4 13.4 C 20.4 18.4 17.4 21.4 12 21.4 C 6.6 21.4 3.6 18.4 3.6 13.4 C 3.6 9.8 5 7.4 7.4 6 Z", 0),
            ("solid", "M 10 13.4 L 10 11.8 C 10 10.6 10.9 9.8 12 9.8 C 13.1 9.8 14 10.6 14 11.8 L 14 13.4", 1.5),
            ("solid", "M 10.2 13 L 13.8 13 C 14.68 13 15.4 13.72 15.4 14.6 L 15.4 16.8 C 15.4 17.68 14.68 18.4 13.8 18.4 L 10.2 18.4 C 9.32 18.4 8.6 17.68 8.6 16.8 L 8.6 14.6 C 8.6 13.72 9.32 13 10.2 13 Z", 0),
            ("hi", "M 12.9 15.6 C 12.9 16.1 12.5 16.5 12 16.5 C 11.5 16.5 11.1 16.1 11.1 15.6 C 11.1 15.1 11.5 14.7 12 14.7 C 12.5 14.7 12.9 15.1 12.9 15.6 Z", 0),
            ("hi", "M 6.36 11.55 C 6.78 10.39 7.55 9.39 8.56 8.69", 1.2),
        ]
        case .navOverview: [
            ("solid", "M 5.6 3 L 8.4 3 C 9.84 3 11 4.16 11 5.6 L 11 8.4 C 11 9.84 9.84 11 8.4 11 L 5.6 11 C 4.16 11 3 9.84 3 8.4 L 3 5.6 C 3 4.16 4.16 3 5.6 3 Z", 0),
            ("soft", "M 15.6 3 L 18.4 3 C 19.84 3 21 4.16 21 5.6 L 21 8.4 C 21 9.84 19.84 11 18.4 11 L 15.6 11 C 14.16 11 13 9.84 13 8.4 L 13 5.6 C 13 4.16 14.16 3 15.6 3 Z", 0),
            ("soft", "M 5.6 13 L 8.4 13 C 9.84 13 11 14.16 11 15.6 L 11 18.4 C 11 19.84 9.84 21 8.4 21 L 5.6 21 C 4.16 21 3 19.84 3 18.4 L 3 15.6 C 3 14.16 4.16 13 5.6 13 Z", 0),
            ("solid", "M 17 20.62 C 15.74 19.54 13.4 17.92 13.4 16.12 C 13.4 14.14 15.92 13.42 17 15.4 C 18.08 13.42 20.6 14.14 20.6 16.12 C 20.6 17.92 18.26 19.54 17 20.62 Z", 0),
        ]
        case .navSpending: [
            ("soft", "M 18.24 8.4 C 19.86 11.22 19.4 14.79 17.09 17.09 C 14.79 19.4 11.22 19.86 8.4 18.24 C 5.58 16.61 4.2 13.28 5.05 10.14 C 5.89 6.99 8.74 4.8 12 4.8", 4.4),
            ("solid", "M 12 1.8 C 16.4 1.8 20.2 4.8 21.4 8.8 L 12 12 Z", 0),
        ]
        case .navTrends: [
            ("soft", "M 5 12 L 5.6 12 C 6.7 12 7.6 12.9 7.6 14 L 7.6 19 C 7.6 20.1 6.7 21 5.6 21 L 5 21 C 3.9 21 3 20.1 3 19 L 3 14 C 3 12.9 3.9 12 5 12 Z", 0),
            ("soft", "M 11.7 8 L 12.3 8 C 13.4 8 14.3 8.9 14.3 10 L 14.3 19 C 14.3 20.1 13.4 21 12.3 21 L 11.7 21 C 10.6 21 9.7 20.1 9.7 19 L 9.7 10 C 9.7 8.9 10.6 8 11.7 8 Z", 0),
            ("solid", "M 18.4 4 L 19 4 C 20.1 4 21 4.9 21 6 L 21 19 C 21 20.1 20.1 21 19 21 L 18.4 21 C 17.3 21 16.4 20.1 16.4 19 L 16.4 6 C 16.4 4.9 17.3 4 18.4 4 Z", 0),
        ]
        case .navWealth: [
            ("soft", "M 4.67 4.84 L 14.8 3.6 C 16.11 3.44 17.31 4.37 17.47 5.69 L 17.62 6.88 C 17.78 8.2 16.84 9.39 15.53 9.56 L 5.4 10.8 C 4.09 10.96 2.89 10.03 2.73 8.71 L 2.58 7.52 C 2.42 6.2 3.36 5.01 4.67 4.84 Z", 0),
            ("solid", "M 6 7.6 L 18 7.6 C 19.99 7.6 21.6 9.21 21.6 11.2 L 21.6 17.2 C 21.6 19.19 19.99 20.8 18 20.8 L 6 20.8 C 4.01 20.8 2.4 19.19 2.4 17.2 L 2.4 11.2 C 2.4 9.21 4.01 7.6 6 7.6 Z", 0),
            ("cut", "M 16.6 11.8 L 20.4 11.8 C 21.73 11.8 22.8 12.87 22.8 14.2 L 22.8 14.4 C 22.8 15.73 21.73 16.8 20.4 16.8 L 16.6 16.8 C 15.27 16.8 14.2 15.73 14.2 14.4 L 14.2 14.2 C 14.2 12.87 15.27 11.8 16.6 11.8 Z", 0),
            ("cut", "M 14.5 14.3 C 14.5 14.36 14.46 14.4 14.4 14.4 C 14.34 14.4 14.3 14.36 14.3 14.3 C 14.3 14.24 14.34 14.2 14.4 14.2 C 14.46 14.2 14.5 14.24 14.5 14.3 Z", 0),
            ("soft", "M 16.9 12.8 L 20.3 12.8 C 21.13 12.8 21.8 13.47 21.8 14.3 L 21.8 14.3 C 21.8 15.13 21.13 15.8 20.3 15.8 L 16.9 15.8 C 16.07 15.8 15.4 15.13 15.4 14.3 L 15.4 14.3 C 15.4 13.47 16.07 12.8 16.9 12.8 Z", 0),
        ]
        case .navPlans: [
            ("soft", "M 1.8 21 C 4 15.4 8 13 12 13 C 16 13 20 15.4 22.2 21 Z", 0),
            ("solid", "M 9 15 L 9 3", 1.8),
            ("solid", "M 9.8 2.6 L 18.4 5.4 C 19.2 5.7 19.2 6.7 18.4 7 L 9.8 9.8 Z", 0),
        ]
        case .navXiaxia: [
            ("soft", "M 13.6 3.2 C 13.6 4.53 12.88 5.6 12 5.6 C 11.12 5.6 10.4 4.53 10.4 3.2 C 10.4 1.87 11.12 0.8 12 0.8 C 12.88 0.8 13.6 1.87 13.6 3.2 Z", 0),
            ("soft", "M 19.35 6.91 C 18.42 7.85 17.15 8.1 16.53 7.47 C 15.9 6.85 16.15 5.58 17.09 4.65 C 18.03 3.71 19.29 3.46 19.92 4.08 C 20.54 4.71 20.29 5.97 19.35 6.91 Z", 0),
            ("soft", "M 20.8 13.6 C 19.47 13.6 18.4 12.88 18.4 12 C 18.4 11.12 19.47 10.4 20.8 10.4 C 22.13 10.4 23.2 11.12 23.2 12 C 23.2 12.88 22.13 13.6 20.8 13.6 Z", 0),
            ("soft", "M 17.09 19.35 C 16.15 18.42 15.9 17.15 16.53 16.53 C 17.15 15.9 18.42 16.15 19.35 17.09 C 20.29 18.03 20.54 19.29 19.92 19.92 C 19.29 20.54 18.03 20.29 17.09 19.35 Z", 0),
            ("soft", "M 10.4 20.8 C 10.4 19.47 11.12 18.4 12 18.4 C 12.88 18.4 13.6 19.47 13.6 20.8 C 13.6 22.13 12.88 23.2 12 23.2 C 11.12 23.2 10.4 22.13 10.4 20.8 Z", 0),
            ("soft", "M 4.65 17.09 C 5.58 16.15 6.85 15.9 7.47 16.53 C 8.1 17.15 7.85 18.42 6.91 19.35 C 5.97 20.29 4.71 20.54 4.08 19.92 C 3.46 19.29 3.71 18.03 4.65 17.09 Z", 0),
            ("soft", "M 3.2 10.4 C 4.53 10.4 5.6 11.12 5.6 12 C 5.6 12.88 4.53 13.6 3.2 13.6 C 1.87 13.6 0.8 12.88 0.8 12 C 0.8 11.12 1.87 10.4 3.2 10.4 Z", 0),
            ("soft", "M 6.91 4.65 C 7.85 5.58 8.1 6.85 7.47 7.47 C 6.85 8.1 5.58 7.85 4.65 6.91 C 3.71 5.97 3.46 4.71 4.08 4.08 C 4.71 3.46 5.97 3.71 6.91 4.65 Z", 0),
            ("solid", "M 18.8 12 C 18.8 15.76 15.76 18.8 12 18.8 C 8.24 18.8 5.2 15.76 5.2 12 C 5.2 8.24 8.24 5.2 12 5.2 C 15.76 5.2 18.8 8.24 18.8 12 Z", 0),
            ("cut", "M 10.6 11.4 C 10.6 12.12 10.15 12.7 9.6 12.7 C 9.05 12.7 8.6 12.12 8.6 11.4 C 8.6 10.68 9.05 10.1 9.6 10.1 C 10.15 10.1 10.6 10.68 10.6 11.4 Z", 0),
            ("cut", "M 15.4 11.4 C 15.4 12.12 14.95 12.7 14.4 12.7 C 13.85 12.7 13.4 12.12 13.4 11.4 C 13.4 10.68 13.85 10.1 14.4 10.1 C 14.95 10.1 15.4 10.68 15.4 11.4 Z", 0),
            ("cut", "M 10 14.2 C 11.2 15.4 12.8 15.4 14 14.2", 1.3),
        ]
        case .navChanges: [
            ("soft", "M 21.2 12.4 C 21.2 17.15 17.35 21 12.6 21 C 7.85 21 4 17.15 4 12.4 C 4 7.65 7.85 3.8 12.6 3.8 C 17.35 3.8 21.2 7.65 21.2 12.4 Z", 0),
            ("solid", "M 12.6 7.8 L 12.6 12.6 L 15.6 14.6", 1.9),
            ("solid", "M 3.2 9.6 C 4.6 5.2 8.4 2.4 12.8 2.4", 1.8),
            ("solid", "M 2.09 5.93 C 1.66 5.85 1.53 6.03 1.75 6.41 L 4.05 10.39 C 4.27 10.77 4.53 10.77 4.75 10.39 L 6.45 7.41 C 6.67 7.03 6.54 6.75 6.11 6.67 Z", 0),
        ]
        case .navTransactions: [
            ("soft", "M 7.6 2.4 L 16.4 2.4 C 18.61 2.4 20.4 4.19 20.4 6.4 L 20.4 17.6 C 20.4 19.81 18.61 21.6 16.4 21.6 L 7.6 21.6 C 5.39 21.6 3.6 19.81 3.6 17.6 L 3.6 6.4 C 3.6 4.19 5.39 2.4 7.6 2.4 Z", 0),
            ("solid", "M 9.2 8 C 9.2 8.77 8.57 9.4 7.8 9.4 C 7.03 9.4 6.4 8.77 6.4 8 C 6.4 7.23 7.03 6.6 7.8 6.6 C 8.57 6.6 9.2 7.23 9.2 8 Z", 0),
            ("solid", "M 11 8 L 16.6 8", 1.8),
            ("solid", "M 9.2 12 C 9.2 12.77 8.57 13.4 7.8 13.4 C 7.03 13.4 6.4 12.77 6.4 12 C 6.4 11.23 7.03 10.6 7.8 10.6 C 8.57 10.6 9.2 11.23 9.2 12 Z", 0),
            ("solid", "M 11 12 L 16.6 12", 1.8),
            ("solid", "M 9.2 16 C 9.2 16.77 8.57 17.4 7.8 17.4 C 7.03 17.4 6.4 16.77 6.4 16 C 6.4 15.23 7.03 14.6 7.8 14.6 C 8.57 14.6 9.2 15.23 9.2 16 Z", 0),
            ("solid", "M 11 16 L 14.6 16", 1.8),
        ]
        case .navSettings: [
            ("soft", "M 9.02 4.8 C 9.18 4.73 9.29 4.6 9.32 4.43 L 9.63 2.92 C 9.75 2.37 10.16 2.04 10.71 2.04 L 13.29 2.04 C 13.84 2.04 14.25 2.37 14.37 2.92 L 14.68 4.43 C 14.71 4.6 14.82 4.73 14.98 4.8 L 14.99 4.8 C 15.14 4.86 15.32 4.85 15.46 4.76 L 16.75 3.9 C 17.21 3.6 17.74 3.65 18.14 4.05 L 19.95 5.86 C 20.35 6.26 20.4 6.79 20.1 7.25 L 19.24 8.54 C 19.15 8.68 19.14 8.86 19.2 9.01 L 19.2 9.02 C 19.27 9.18 19.4 9.29 19.57 9.32 L 21.08 9.63 C 21.63 9.75 21.96 10.16 21.96 10.71 L 21.96 13.29 C 21.96 13.84 21.63 14.25 21.08 14.37 L 19.57 14.68 C 19.4 14.71 19.27 14.82 19.2 14.98 L 19.2 14.99 C 19.14 15.14 19.15 15.32 19.24 15.46 L 20.1 16.75 C 20.4 17.21 20.35 17.74 19.95 18.14 L 18.14 19.95 C 17.74 20.35 17.21 20.4 16.75 20.1 L 15.46 19.24 C 15.32 19.15 15.14 19.14 14.99 19.2 L 14.98 19.2 C 14.82 19.27 14.71 19.4 14.68 19.57 L 14.37 21.08 C 14.25 21.63 13.84 21.96 13.29 21.96 L 10.71 21.96 C 10.16 21.96 9.75 21.63 9.63 21.08 L 9.32 19.57 C 9.29 19.4 9.18 19.27 9.02 19.2 L 9.01 19.2 C 8.86 19.14 8.68 19.15 8.54 19.24 L 7.25 20.1 C 6.79 20.4 6.26 20.35 5.86 19.95 L 4.05 18.14 C 3.65 17.74 3.6 17.21 3.9 16.75 L 4.76 15.46 C 4.85 15.32 4.86 15.14 4.8 14.99 L 4.8 14.98 C 4.73 14.82 4.6 14.71 4.43 14.68 L 2.92 14.37 C 2.37 14.25 2.04 13.84 2.04 13.29 L 2.04 10.71 C 2.04 10.16 2.37 9.75 2.92 9.63 L 4.43 9.32 C 4.6 9.29 4.73 9.18 4.8 9.02 L 4.8 9.01 C 4.86 8.86 4.85 8.68 4.76 8.54 L 3.9 7.25 C 3.6 6.79 3.65 6.26 4.05 5.86 L 5.86 4.05 C 6.26 3.65 6.79 3.6 7.25 3.9 L 8.54 4.76 C 8.68 4.85 8.86 4.86 9.01 4.8 Z", 0),
            ("solid", "M 16.4 12 C 16.4 14.43 14.43 16.4 12 16.4 C 9.57 16.4 7.6 14.43 7.6 12 C 7.6 9.57 9.57 7.6 12 7.6 C 14.43 7.6 16.4 9.57 16.4 12 Z", 0),
            ("cut", "M 13.8 12 C 13.8 12.99 12.99 13.8 12 13.8 C 11.01 13.8 10.2 12.99 10.2 12 C 10.2 11.01 11.01 10.2 12 10.2 C 12.99 10.2 13.8 11.01 13.8 12 Z", 0),
        ]
        case .actAdd: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 12 7.4 L 12 16.6", 2.4),
            ("solid", "M 7.4 12 L 16.6 12", 2.4),
        ]
        case .actAsk: [
            ("solid", "M 10.4 4.4 C 11.95 11.45 11.95 11.45 19 13 C 11.95 14.55 11.95 14.55 10.4 21.6 C 8.85 14.55 8.85 14.55 1.8 13 C 8.85 11.45 8.85 11.45 10.4 4.4 Z", 0),
            ("soft", "M 18.8 1.6 C 19.45 4.55 19.45 4.55 22.4 5.2 C 19.45 5.85 19.45 5.85 18.8 8.8 C 18.15 5.85 18.15 5.85 15.2 5.2 C 18.15 4.55 18.15 4.55 18.8 1.6 Z", 0),
            ("soft", "M 19.2 16.2 C 19.68 18.12 19.68 18.12 21.6 18.6 C 19.68 19.08 19.68 19.08 19.2 21 C 18.72 19.08 18.72 19.08 16.8 18.6 C 18.72 18.12 18.72 18.12 19.2 16.2 Z", 0),
        ]
        case .actChat: [
            ("soft", "M 12 3 C 17.2 3 21 6.6 21 11 C 21 15.4 17.2 19 12 19 C 11 19 10 18.8 9.2 18.6 L 5 21 L 5.6 16.8 C 4 15.4 3 13.4 3 11 C 3 6.6 6.8 3 12 3 Z", 0),
            ("solid", "M 9.7 11 C 9.7 11.72 9.12 12.3 8.4 12.3 C 7.68 12.3 7.1 11.72 7.1 11 C 7.1 10.28 7.68 9.7 8.4 9.7 C 9.12 9.7 9.7 10.28 9.7 11 Z", 0),
            ("solid", "M 13.3 11 C 13.3 11.72 12.72 12.3 12 12.3 C 11.28 12.3 10.7 11.72 10.7 11 C 10.7 10.28 11.28 9.7 12 9.7 C 12.72 9.7 13.3 10.28 13.3 11 Z", 0),
            ("solid", "M 16.9 11 C 16.9 11.72 16.32 12.3 15.6 12.3 C 14.88 12.3 14.3 11.72 14.3 11 C 14.3 10.28 14.88 9.7 15.6 9.7 C 16.32 9.7 16.9 10.28 16.9 11 Z", 0),
        ]
        case .actEdit: [
            ("soft", "M 15.25 5.92 L 18.08 8.75 C 18.32 8.98 18.32 9.36 18.08 9.6 L 10.3 17.37 C 10.07 17.61 9.69 17.61 9.45 17.37 L 6.63 14.55 C 6.39 14.31 6.39 13.93 6.63 13.7 L 14.4 5.92 C 14.64 5.68 15.02 5.68 15.25 5.92 Z", 0),
            ("solid", "M 19.42 3.87 L 20.13 4.58 C 20.95 5.4 20.95 6.73 20.13 7.55 L 18.93 8.75 C 18.77 8.9 18.52 8.9 18.36 8.75 L 15.25 5.64 C 15.1 5.48 15.1 5.23 15.25 5.07 L 16.45 3.87 C 17.27 3.05 18.6 3.05 19.42 3.87 Z", 0),
            ("solid", "M 5.79 15.12 C 5.96 14.59 6.3 14.5 6.7 14.9 L 9.1 17.3 C 9.5 17.7 9.41 18.04 8.88 18.21 L 5.22 19.37 C 4.69 19.53 4.47 19.31 4.63 18.78 Z", 0),
            ("hi", "M 14.55 8.04 L 9.45 13.13", 1.1),
        ]
        case .actDelete: [
            ("soft", "M 5 7.6 L 19 7.6 L 17.8 19.4 C 17.6 20.6 16.6 21.4 15.4 21.4 L 8.6 21.4 C 7.4 21.4 6.4 20.6 6.2 19.4 Z", 0),
            ("solid", "M 4.5 5 L 19.5 5 C 20.33 5 21 5.67 21 6.5 L 21 6.5 C 21 7.33 20.33 8 19.5 8 L 4.5 8 C 3.67 8 3 7.33 3 6.5 L 3 6.5 C 3 5.67 3.67 5 4.5 5 Z", 0),
            ("solid", "M 10.4 2.4 L 13.6 2.4 C 14.37 2.4 15 3.03 15 3.8 L 15 4.4 C 15 5.17 14.37 5.8 13.6 5.8 L 10.4 5.8 C 9.63 5.8 9 5.17 9 4.4 L 9 3.8 C 9 3.03 9.63 2.4 10.4 2.4 Z", 0),
            ("solid", "M 10 11.4 L 10 17.4", 1.6),
            ("solid", "M 14 11.4 L 14 17.4", 1.6),
        ]
        case .actUndo: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 8 10.4 L 14 10.4 C 16 10.4 17.4 11.8 17.4 13.8 C 17.4 15.8 16 17.2 14 17.2 L 11 17.2", 2),
            ("solid", "M 9.6 7.4 C 9.6 6.9 9.37 6.8 9.01 7.14 L 5.99 9.86 C 5.63 10.2 5.63 10.6 5.99 10.94 L 9.01 13.66 C 9.37 14 9.6 13.9 9.6 13.4 Z", 0),
        ]
        case .actSearch: [
            ("soft", "M 17.8 10.4 C 17.8 14.49 14.49 17.8 10.4 17.8 C 6.31 17.8 3 14.49 3 10.4 C 3 6.31 6.31 3 10.4 3 C 14.49 3 17.8 6.31 17.8 10.4 Z", 0),
            ("solid", "M 17.8 10.4 C 17.8 14.49 14.49 17.8 10.4 17.8 C 6.31 17.8 3 14.49 3 10.4 C 3 6.31 6.31 3 10.4 3 C 14.49 3 17.8 6.31 17.8 10.4 Z", 2.2),
            ("solid", "M 16 16 L 20.8 20.8", 3.2),
            ("hi", "M 6.45 8.96 C 6.88 7.8 7.8 6.88 8.96 6.45", 1.4),
        ]
        case .actFilter: [
            ("soft", "M 3.77 5.36 C 3.05 4.52 3.28 4 4.4 4 L 19.6 4 C 20.72 4 20.95 4.52 20.23 5.36 L 15.17 11.24 C 14.45 12.08 13.32 12.6 12.2 12.6 L 11.8 12.6 C 10.68 12.6 9.55 12.08 8.83 11.24 Z", 0),
            ("solid", "M 10 12 L 14 12 L 14 19.2 C 14 19.8 13.6 20.2 13.2 20.4 L 11 21.4 C 10.5 21.6 10 21.3 10 20.7 Z", 0),
        ]
        case .actCopy: [
            ("soft", "M 6 3 L 12 3 C 13.66 3 15 4.34 15 6 L 15 14 C 15 15.66 13.66 17 12 17 L 6 17 C 4.34 17 3 15.66 3 14 L 3 6 C 3 4.34 4.34 3 6 3 Z", 0),
            ("solid", "M 12 7 L 18 7 C 19.66 7 21 8.34 21 10 L 21 18 C 21 19.66 19.66 21 18 21 L 12 21 C 10.34 21 9 19.66 9 18 L 9 10 C 9 8.34 10.34 7 12 7 Z", 0),
            ("hi", "M 12 12 L 17.6 12", 1.4),
            ("hi", "M 12 15.6 L 15.6 15.6", 1.4),
        ]
        case .actImport: [
            ("soft", "M 3 13 L 8.4 13 C 8.8 15 10.2 16.2 12 16.2 C 13.8 16.2 15.2 15 15.6 13 L 21 13 L 21 18 C 21 19.8 19.8 21 18 21 L 6 21 C 4.2 21 3 19.8 3 18 Z", 0),
            ("solid", "M 12 2.6 L 12 10.4", 2.2),
            ("solid", "M 8.8 8.6 C 8.3 8.6 8.2 8.82 8.54 9.19 L 11.46 12.41 C 11.8 12.78 12.2 12.78 12.54 12.41 L 15.46 9.19 C 15.8 8.82 15.7 8.6 15.2 8.6 Z", 0),
        ]
        case .actExport: [
            ("soft", "M 3 13 L 8.4 13 C 8.8 15 10.2 16.2 12 16.2 C 13.8 16.2 15.2 15 15.6 13 L 21 13 L 21 18 C 21 19.8 19.8 21 18 21 L 6 21 C 4.2 21 3 19.8 3 18 Z", 0),
            ("solid", "M 12 12.4 L 12 5", 2.2),
            ("solid", "M 8.8 6.6 C 8.3 6.6 8.2 6.38 8.54 6.01 L 11.46 2.79 C 11.8 2.42 12.2 2.42 12.54 2.79 L 15.46 6.01 C 15.8 6.38 15.7 6.6 15.2 6.6 Z", 0),
        ]
        case .actSync: [
            ("soft", "M 7 19.4 C 4.2 19.4 2 17.2 2 14.4 C 2 11.8 4 9.6 6.6 9.4 C 7.4 6.2 10 4 13.2 4 C 17 4 20 6.8 20.4 10.4 C 22.2 11 23.2 12.6 23.2 14.6 C 23.2 17.2 21.2 19.4 18.6 19.4 Z", 0),
            ("solid", "M 9.03 11.3 C 9.53 9.91 10.8 8.94 12.27 8.81 C 13.74 8.69 15.15 9.42 15.89 10.7", 1.8),
            ("solid", "M 16.07 8.78 C 16.28 8.54 16.45 8.58 16.52 8.89 L 17.08 11.11 C 17.15 11.42 17.01 11.58 16.7 11.54 L 14.5 11.26 C 14.19 11.22 14.12 11.06 14.33 10.82 Z", 0),
            ("solid", "M 16.17 13.9 C 15.67 15.29 14.4 16.26 12.93 16.39 C 11.46 16.51 10.05 15.78 9.31 14.5", 1.8),
            ("solid", "M 9.13 16.42 C 8.92 16.66 8.75 16.62 8.68 16.31 L 8.12 14.09 C 8.05 13.78 8.19 13.62 8.5 13.66 L 10.7 13.94 C 11.01 13.98 11.08 14.14 10.87 14.38 Z", 0),
        ]
        case .actHide: [
            ("soft", "M 12 5.4 C 17 5.4 20.6 8.8 22 12 C 20.6 15.2 17 18.6 12 18.6 C 7 18.6 3.4 15.2 2 12 C 3.4 8.8 7 5.4 12 5.4 Z", 0),
            ("solid", "M 15.4 12 C 15.4 13.88 13.88 15.4 12 15.4 C 10.12 15.4 8.6 13.88 8.6 12 C 8.6 10.12 10.12 8.6 12 8.6 C 13.88 8.6 15.4 10.12 15.4 12 Z", 0),
            ("cut", "M 2.81 2.81 L 2.81 2.81 C 3.51 2.1 4.65 2.1 5.35 2.81 L 21.19 18.65 C 21.9 19.35 21.9 20.49 21.19 21.19 L 21.19 21.19 C 20.49 21.9 19.35 21.9 18.65 21.19 L 2.81 5.35 C 2.1 4.65 2.1 3.51 2.81 2.81 Z", 0),
            ("solid", "M 4.2 3.8 L 20.2 19.8", 1.9),
        ]
        case .actShow: [
            ("soft", "M 12 5.4 C 17 5.4 20.6 8.8 22 12 C 20.6 15.2 17 18.6 12 18.6 C 7 18.6 3.4 15.2 2 12 C 3.4 8.8 7 5.4 12 5.4 Z", 0),
            ("solid", "M 15.8 12 C 15.8 14.1 14.1 15.8 12 15.8 C 9.9 15.8 8.2 14.1 8.2 12 C 8.2 9.9 9.9 8.2 12 8.2 C 14.1 8.2 15.8 9.9 15.8 12 Z", 0),
            ("hi", "M 10.12 11.32 C 10.36 10.64 10.95 10.15 11.65 10.03", 1.2),
        ]
        case .actCalendar: [
            ("soft", "M 6.4 4.6 L 17.6 4.6 C 19.48 4.6 21 6.12 21 8 L 21 17.8 C 21 19.68 19.48 21.2 17.6 21.2 L 6.4 21.2 C 4.52 21.2 3 19.68 3 17.8 L 3 8 C 3 6.12 4.52 4.6 6.4 4.6 Z", 0),
            ("solid", "M 5.7 4.6 L 18.3 4.6 C 19.79 4.6 21 5.81 21 7.3 L 21 10 L 3 10 L 3 7.3 C 3 5.81 4.21 4.6 5.7 4.6 Z", 0),
            ("solid", "M 8.1 2.4 L 8.1 2.4 C 8.71 2.4 9.2 2.89 9.2 3.5 L 9.2 5.9 C 9.2 6.51 8.71 7 8.1 7 L 8.1 7 C 7.49 7 7 6.51 7 5.9 L 7 3.5 C 7 2.89 7.49 2.4 8.1 2.4 Z", 0),
            ("solid", "M 15.9 2.4 L 15.9 2.4 C 16.51 2.4 17 2.89 17 3.5 L 17 5.9 C 17 6.51 16.51 7 15.9 7 L 15.9 7 C 15.29 7 14.8 6.51 14.8 5.9 L 14.8 3.5 C 14.8 2.89 15.29 2.4 15.9 2.4 Z", 0),
            ("solid", "M 12 17.47 C 11.09 16.69 9.4 15.52 9.4 14.22 C 9.4 12.79 11.22 12.27 12 13.7 C 12.78 12.27 14.6 12.79 14.6 14.22 C 14.6 15.52 12.91 16.69 12 17.47 Z", 0),
        ]
        case .actBooks: [
            ("soft", "M 4.8 4 L 6.2 4 C 7.19 4 8 4.81 8 5.8 L 8 19.2 C 8 20.19 7.19 21 6.2 21 L 4.8 21 C 3.81 21 3 20.19 3 19.2 L 3 5.8 C 3 4.81 3.81 4 4.8 4 Z", 0),
            ("solid", "M 10.8 2.6 L 12.2 2.6 C 13.19 2.6 14 3.41 14 4.4 L 14 19.2 C 14 20.19 13.19 21 12.2 21 L 10.8 21 C 9.81 21 9 20.19 9 19.2 L 9 4.4 C 9 3.41 9.81 2.6 10.8 2.6 Z", 0),
            ("soft", "M 14.91 5.6 L 16.27 5.27 C 17.23 5.02 18.21 5.61 18.45 6.58 L 21.4 18.41 C 21.64 19.38 21.05 20.36 20.09 20.6 L 18.73 20.93 C 17.77 21.18 16.79 20.59 16.55 19.62 L 13.6 7.79 C 13.36 6.82 13.95 5.84 14.91 5.6 Z", 0),
            ("hi", "M 11.5 6.4 L 11.5 8.6", 1.3),
        ]
        case .actMore: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 9 12 C 9 12.88 8.28 13.6 7.4 13.6 C 6.52 13.6 5.8 12.88 5.8 12 C 5.8 11.12 6.52 10.4 7.4 10.4 C 8.28 10.4 9 11.12 9 12 Z", 0),
            ("solid", "M 13.6 12 C 13.6 12.88 12.88 13.6 12 13.6 C 11.12 13.6 10.4 12.88 10.4 12 C 10.4 11.12 11.12 10.4 12 10.4 C 12.88 10.4 13.6 11.12 13.6 12 Z", 0),
            ("solid", "M 18.2 12 C 18.2 12.88 17.48 13.6 16.6 13.6 C 15.72 13.6 15 12.88 15 12 C 15 11.12 15.72 10.4 16.6 10.4 C 17.48 10.4 18.2 11.12 18.2 12 Z", 0),
        ]
        case .actClose: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 8.6 8.6 L 15.4 15.4", 2.2),
            ("solid", "M 15.4 8.6 L 8.6 15.4", 2.2),
        ]
        case .actCheck: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 7.4 12.4 L 10.6 15.6 L 16.8 8.8", 2.4),
        ]
        case .actLink: [
            ("soft", "M 4.73 12.28 L 7.98 9.03 C 9.39 7.62 11.67 7.62 13.07 9.03 L 13.07 9.03 C 14.48 10.43 14.48 12.71 13.07 14.12 L 9.82 17.37 C 8.41 18.78 6.13 18.78 4.73 17.37 L 4.73 17.37 C 3.32 15.97 3.32 13.69 4.73 12.28 Z", 2.4),
            ("solid", "M 10.93 9.88 L 14.18 6.63 C 15.59 5.22 17.87 5.22 19.27 6.63 L 19.27 6.63 C 20.68 8.03 20.68 10.31 19.27 11.72 L 16.02 14.97 C 14.61 16.38 12.33 16.38 10.93 14.97 L 10.93 14.97 C 9.52 13.57 9.52 11.29 10.93 9.88 Z", 2.4),
        ]
        case .actLock: [
            ("solid", "M 7.6 11 L 7.6 8 C 7.6 5.4 9.6 3.4 12 3.4 C 14.4 3.4 16.4 5.4 16.4 8 L 16.4 11", 2.2),
            ("soft", "M 7.4 10 L 16.6 10 C 18.48 10 20 11.52 20 13.4 L 20 18 C 20 19.88 18.48 21.4 16.6 21.4 L 7.4 21.4 C 5.52 21.4 4 19.88 4 18 L 4 13.4 C 4 11.52 5.52 10 7.4 10 Z", 0),
            ("solid", "M 12 17.68 C 11.16 16.96 9.6 15.88 9.6 14.68 C 9.6 13.36 11.28 12.88 12 14.2 C 12.72 12.88 14.4 13.36 14.4 14.68 C 14.4 15.88 12.84 16.96 12 17.68 Z", 0),
        ]
        case .actBell: [
            ("soft", "M 12 3 C 15.8 3 18.4 5.8 18.4 9.6 L 18.4 13.4 L 20.4 16.6 C 20.8 17.2 20.4 18 19.6 18 L 4.4 18 C 3.6 18 3.2 17.2 3.6 16.6 L 5.6 13.4 L 5.6 9.6 C 5.6 5.8 8.2 3 12 3 Z", 0),
            ("solid", "M 9.2 19.2 L 14.8 19.2 C 14.6 20.6 13.4 21.6 12 21.6 C 10.6 21.6 9.4 20.6 9.2 19.2 Z", 0),
            ("solid", "M 20.6 5 C 20.6 6.66 19.26 8 17.6 8 C 15.94 8 14.6 6.66 14.6 5 C 14.6 3.34 15.94 2 17.6 2 C 19.26 2 20.6 3.34 20.6 5 Z", 0),
        ]
        case .actScan: [
            ("solid", "M 3 8 L 3 6 C 3 4.4 4.4 3 6 3 L 8 3", 2),
            ("solid", "M 16 3 L 18 3 C 19.6 3 21 4.4 21 6 L 21 8", 2),
            ("solid", "M 21 16 L 21 18 C 21 19.6 19.6 21 18 21 L 16 21", 2),
            ("solid", "M 8 21 L 6 21 C 4.4 21 3 19.6 3 18 L 3 16", 2),
            ("soft", "M 9 6.4 L 15 6.4 C 16.1 6.4 17 7.3 17 8.4 L 17 15.6 C 17 16.7 16.1 17.6 15 17.6 L 9 17.6 C 7.9 17.6 7 16.7 7 15.6 L 7 8.4 C 7 7.3 7.9 6.4 9 6.4 Z", 0),
            ("solid", "M 9.6 10 L 14.4 10", 1.5),
            ("solid", "M 9.6 13.4 L 12.6 13.4", 1.5),
        ]
        case .actShare: [
            ("soft", "M 6 9 L 8 9 L 8 11 L 6.6 11 L 6.6 19 L 17.4 19 L 17.4 11 L 16 11 L 16 9 L 18 9 C 19 9 19.6 9.6 19.6 10.6 L 19.6 19.4 C 19.6 20.4 19 21 18 21 L 6 21 C 5 21 4.4 20.4 4.4 19.4 L 4.4 10.6 C 4.4 9.6 5 9 6 9 Z", 0),
            ("soft", "M 7 10 L 17 10 C 17.77 10 18.4 10.63 18.4 11.4 L 18.4 18.6 C 18.4 19.37 17.77 20 17 20 L 7 20 C 6.23 20 5.6 19.37 5.6 18.6 L 5.6 11.4 C 5.6 10.63 6.23 10 7 10 Z", 0),
            ("solid", "M 12 14.4 L 12 3.6", 2.2),
            ("solid", "M 9 6.6 C 8.5 6.6 8.4 6.37 8.74 6.01 L 11.46 2.99 C 11.8 2.63 12.2 2.63 12.54 2.99 L 15.26 6.01 C 15.6 6.37 15.5 6.6 15 6.6 Z", 0),
        ]
        case .badgeAi: [
            ("solid", "M 10 5 C 11.44 11.56 11.44 11.56 18 13 C 11.44 14.44 11.44 14.44 10 21 C 8.56 14.44 8.56 14.44 2 13 C 8.56 11.56 8.56 11.56 10 5 Z", 0),
            ("soft", "M 18.6 1.8 C 19.25 4.75 19.25 4.75 22.2 5.4 C 19.25 6.05 19.25 6.05 18.6 9 C 17.95 6.05 17.95 6.05 15 5.4 C 17.95 4.75 17.95 4.75 18.6 1.8 Z", 0),
        ]
        case .badgeMe: [
            ("soft", "M 3.4 21 C 3.4 16.6 7.2 14 12 14 C 16.8 14 20.6 16.6 20.6 21 Z", 0),
            ("solid", "M 16.8 8 C 16.8 10.65 14.65 12.8 12 12.8 C 9.35 12.8 7.2 10.65 7.2 8 C 7.2 5.35 9.35 3.2 12 3.2 C 14.65 3.2 16.8 5.35 16.8 8 Z", 0),
        ]
        case .badgeWarn: [
            ("soft", "M 10.53 5.22 C 11.44 3.59 12.56 3.59 13.47 5.22 L 20.53 17.78 C 21.44 19.41 20.86 20.4 19 20.4 L 5 20.4 C 3.14 20.4 2.56 19.41 3.47 17.78 Z", 0),
            ("solid", "M 12 9 L 12 13.6", 2.4),
            ("solid", "M 13.4 17 C 13.4 17.77 12.77 18.4 12 18.4 C 11.23 18.4 10.6 17.77 10.6 17 C 10.6 16.23 11.23 15.6 12 15.6 C 12.77 15.6 13.4 16.23 13.4 17 Z", 0),
        ]
        case .badgeAlert: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 12 6.8 L 12 13", 2.6),
            ("solid", "M 13.5 16.8 C 13.5 17.63 12.83 18.3 12 18.3 C 11.17 18.3 10.5 17.63 10.5 16.8 C 10.5 15.97 11.17 15.3 12 15.3 C 12.83 15.3 13.5 15.97 13.5 16.8 Z", 0),
        ]
        case .badgeDone: [
            ("soft", "M 10.99 3.93 C 11.62 2.86 12.38 2.86 13.01 3.93 L 14.36 6.24 C 14.98 7.32 16.1 8.13 17.32 8.4 L 19.94 8.96 C 21.15 9.23 21.38 9.95 20.56 10.88 L 18.77 12.88 C 17.95 13.8 17.52 15.12 17.64 16.36 L 17.91 19.02 C 18.04 20.26 17.42 20.71 16.28 20.21 L 13.83 19.13 C 12.7 18.63 11.3 18.63 10.17 19.13 L 7.72 20.21 C 6.58 20.71 5.96 20.26 6.09 19.02 L 6.36 16.36 C 6.48 15.12 6.05 13.8 5.23 12.88 L 3.44 10.88 C 2.62 9.95 2.85 9.23 4.06 8.96 L 6.68 8.4 C 7.9 8.13 9.02 7.32 9.64 6.24 Z", 0),
            ("solid", "M 16.4 12.6 C 16.4 15.03 14.43 17 12 17 C 9.57 17 7.6 15.03 7.6 12.6 C 7.6 10.17 9.57 8.2 12 8.2 C 14.43 8.2 16.4 10.17 16.4 12.6 Z", 0),
            ("hi", "M 10 12.8 L 11.6 14.2 L 14 11.4", 1.4),
        ]
        case .badgeRepeat: [
            ("soft", "M 22 12 C 22 17.52 17.52 22 12 22 C 6.48 22 2 17.52 2 12 C 2 6.48 6.48 2 12 2 C 17.52 2 22 6.48 22 12 Z", 0),
            ("solid", "M 6.74 10.08 C 7.48 8.04 9.34 6.61 11.51 6.42 C 13.68 6.23 15.76 7.32 16.85 9.2", 2),
            ("solid", "M 16.17 6.84 C 16.31 6.57 16.5 6.56 16.65 6.83 L 18.15 9.37 C 18.3 9.64 18.21 9.8 17.9 9.8 L 15.1 9.8 C 14.79 9.8 14.69 9.63 14.83 9.36 Z", 0),
            ("solid", "M 17.26 13.92 C 16.52 15.96 14.66 17.39 12.49 17.58 C 10.32 17.77 8.24 16.68 7.15 14.8", 2),
            ("solid", "M 7.83 17.16 C 7.69 17.43 7.5 17.44 7.35 17.17 L 5.85 14.63 C 5.7 14.36 5.79 14.2 6.1 14.2 L 8.9 14.2 C 9.21 14.2 9.31 14.37 9.17 14.64 Z", 0),
        ]
        case .badgeNew: [
            ("soft", "M 10.99 3.73 C 11.62 2.66 12.38 2.66 13.01 3.73 L 14.36 6.04 C 14.98 7.12 16.1 7.93 17.32 8.2 L 19.94 8.76 C 21.15 9.03 21.38 9.75 20.56 10.68 L 18.77 12.68 C 17.95 13.6 17.52 14.92 17.64 16.16 L 17.91 18.82 C 18.04 20.06 17.42 20.51 16.28 20.01 L 13.83 18.93 C 12.7 18.43 11.3 18.43 10.17 18.93 L 7.72 20.01 C 6.58 20.51 5.96 20.06 6.09 18.82 L 6.36 16.16 C 6.48 14.92 6.05 13.6 5.23 12.68 L 3.44 10.68 C 2.62 9.75 2.85 9.03 4.06 8.76 L 6.68 8.2 C 7.9 7.93 9.02 7.12 9.64 6.04 Z", 0),
            ("solid", "M 11.65 7.92 C 11.87 7.47 12.13 7.47 12.35 7.92 L 13.17 9.58 C 13.39 10.02 13.83 10.34 14.32 10.41 L 16.15 10.68 C 16.64 10.75 16.73 11.01 16.37 11.35 L 15.05 12.65 C 14.69 12.99 14.52 13.5 14.61 13.99 L 14.92 15.82 C 15.01 16.31 14.79 16.47 14.35 16.23 L 12.71 15.37 C 12.27 15.14 11.73 15.14 11.29 15.37 L 9.65 16.23 C 9.21 16.47 8.99 16.31 9.08 15.82 L 9.39 13.99 C 9.48 13.5 9.31 12.99 8.95 12.65 L 7.63 11.35 C 7.27 11.01 7.36 10.75 7.85 10.68 L 9.68 10.41 C 10.17 10.34 10.61 10.02 10.83 9.58 Z", 0),
        ]
        case .badgeSynced: [
            ("soft", "M 7 19.4 C 4.2 19.4 2 17.2 2 14.4 C 2 11.8 4 9.6 6.6 9.4 C 7.4 6.2 10 4 13.2 4 C 17 4 20 6.8 20.4 10.4 C 22.2 11 23.2 12.6 23.2 14.6 C 23.2 17.2 21.2 19.4 18.6 19.4 Z", 0),
            ("solid", "M 9 13 L 11.6 15.4 L 16.4 10.2", 2.2),
        ]
        case .badgeOffline: [
            ("soft", "M 7 19.4 C 4.2 19.4 2 17.2 2 14.4 C 2 11.8 4 9.6 6.6 9.4 C 7.4 6.2 10 4 13.2 4 C 17 4 20 6.8 20.4 10.4 C 22.2 11 23.2 12.6 23.2 14.6 C 23.2 17.2 21.2 19.4 18.6 19.4 Z", 0),
            ("solid", "M 9.4 9.4 L 16 16", 2.2),
            ("solid", "M 16 9.4 L 9.4 16", 2.2),
        ]
        case .badgePrivate: [
            ("soft", "M 12 20.72 C 8.64 17.84 2.4 13.52 2.4 8.72 C 2.4 3.44 9.12 1.52 12 6.8 C 14.88 1.52 21.6 3.44 21.6 8.72 C 21.6 13.52 15.36 17.84 12 20.72 Z", 0),
            ("solid", "M 12 15.98 C 10.46 14.66 7.6 12.68 7.6 10.48 C 7.6 8.06 10.68 7.18 12 9.6 C 13.32 7.18 16.4 8.06 16.4 10.48 C 16.4 12.68 13.54 14.66 12 15.98 Z", 0),
        ]
        case .delivery: [
            ("solid", "M 9 18.4 C 9 19.84 7.84 21 6.4 21 C 4.96 21 3.8 19.84 3.8 18.4 C 3.8 16.96 4.96 15.8 6.4 15.8 C 7.84 15.8 9 16.96 9 18.4 Z", 0),
            ("solid", "M 20.6 18.4 C 20.6 19.84 19.44 21 18 21 C 16.56 21 15.4 19.84 15.4 18.4 C 15.4 16.96 16.56 15.8 18 15.8 C 19.44 15.8 20.6 16.96 20.6 18.4 Z", 0),
            ("soft", "M 4 16.6 C 4 13.6 6 11.8 8.6 11.8 L 13 11.8 L 14.6 15.4 L 17.4 15.4 L 15.4 9 L 18.2 9 L 21 16.6 Z", 0),
            ("solid", "M 4.8 4.4 L 10 4.4 C 11.22 4.4 12.2 5.38 12.2 6.6 L 12.2 9.6 C 12.2 10.82 11.22 11.8 10 11.8 L 4.8 11.8 C 3.58 11.8 2.6 10.82 2.6 9.6 L 2.6 6.6 C 2.6 5.38 3.58 4.4 4.8 4.4 Z", 0),
            ("hi", "M 7.4 9.32 C 6.84 8.84 5.8 8.12 5.8 7.32 C 5.8 6.44 6.92 6.12 7.4 7 C 7.88 6.12 9 6.44 9 7.32 C 9 8.12 7.96 8.84 7.4 9.32 Z", 0),
            ("hi", "M 7.3 18.4 C 7.3 18.9 6.9 19.3 6.4 19.3 C 5.9 19.3 5.5 18.9 5.5 18.4 C 5.5 17.9 5.9 17.5 6.4 17.5 C 6.9 17.5 7.3 17.9 7.3 18.4 Z", 0),
            ("hi", "M 18.9 18.4 C 18.9 18.9 18.5 19.3 18 19.3 C 17.5 19.3 17.1 18.9 17.1 18.4 C 17.1 17.9 17.5 17.5 18 17.5 C 18.5 17.5 18.9 17.9 18.9 18.4 Z", 0),
        ]
        case .breakfast: [
            ("soft", "M 5 9.6 C 3.4 9.6 2.4 8.4 2.4 7 C 2.4 4.6 5 3 8 3 L 16 3 C 19 3 21.6 4.6 21.6 7 C 21.6 8.4 20.6 9.6 19 9.6 L 19 19 C 19 20.2 18 21 17 21 L 7 21 C 6 21 5 20.2 5 19 Z", 0),
            ("white", "M 17 13.6 C 17 16.03 14.76 18 12 18 C 9.24 18 7 16.03 7 13.6 C 7 11.17 9.24 9.2 12 9.2 C 14.76 9.2 17 11.17 17 13.6 Z", 0),
            ("solid", "M 14.6 13.8 C 14.6 15.24 13.44 16.4 12 16.4 C 10.56 16.4 9.4 15.24 9.4 13.8 C 9.4 12.36 10.56 11.2 12 11.2 C 13.44 11.2 14.6 12.36 14.6 13.8 Z", 0),
            ("hi", "M 12 13 C 12 13.44 11.64 13.8 11.2 13.8 C 10.76 13.8 10.4 13.44 10.4 13 C 10.4 12.56 10.76 12.2 11.2 12.2 C 11.64 12.2 12 12.56 12 13 Z", 0),
        ]
        case .fruit: [
            ("solid", "M 12 7.4 C 14.2 5.8 20 5.6 20.4 11.8 C 20.8 17.6 16.8 21.6 14.4 21.6 C 13.2 21.6 12.8 21 12 21 C 11.2 21 10.8 21.6 9.6 21.6 C 7.2 21.6 3.2 17.6 3.6 11.8 C 4 5.6 9.8 5.8 12 7.4 Z", 0),
            ("solid", "M 12 7.4 C 12 5.4 12.6 3.8 13.8 2.6", 1.6),
            ("leaf", "M 13.4 4.4 C 15 2.4 18 2.2 19.4 3.4 C 18 5.4 15.2 5.8 13.4 4.4 Z", 0),
            ("hi", "M 6 11.6 C 6 10.68 6.58 9.85 7.45 9.53", 1.3),
        ]
        case .dessert: [
            ("solid", "M 5.35 13.96 C 5.13 12.99 5.61 12.4 6.6 12.4 L 17.4 12.4 C 18.39 12.4 18.87 12.99 18.65 13.96 L 17.35 19.64 C 17.13 20.61 16.39 21.2 15.4 21.2 L 8.6 21.2 C 7.61 21.2 6.87 20.61 6.65 19.64 Z", 0),
            ("hi", "M 9.4 14.6 L 10 19.2", 1.1),
            ("hi", "M 14.6 14.6 L 14 19.2", 1.1),
            ("soft", "M 4 12.4 C 3 12.4 2.8 10.6 4 9.8 C 4 6.6 6.6 4.8 9 5.2 C 10 3.4 14 3.4 15 5.2 C 17.4 4.8 20 6.6 20 9.8 C 21.2 10.6 21 12.4 20 12.4 Z", 0),
            ("solid", "M 13.8 3.6 C 13.8 4.59 12.99 5.4 12 5.4 C 11.01 5.4 10.2 4.59 10.2 3.6 C 10.2 2.61 11.01 1.8 12 1.8 C 12.99 1.8 13.8 2.61 13.8 3.6 Z", 0),
            ("hi", "M 9.4 8.4 C 9.4 8.84 9.04 9.2 8.6 9.2 C 8.16 9.2 7.8 8.84 7.8 8.4 C 7.8 7.96 8.16 7.6 8.6 7.6 C 9.04 7.6 9.4 7.96 9.4 8.4 Z", 0),
            ("hi", "M 15.8 9.2 C 15.8 9.64 15.44 10 15 10 C 14.56 10 14.2 9.64 14.2 9.2 C 14.2 8.76 14.56 8.4 15 8.4 C 15.44 8.4 15.8 8.76 15.8 9.2 Z", 0),
        ]
        case .bubbletea: [
            ("solid", "M 13 1.8 L 15.6 8.6", 1.8),
            ("soft", "M 5.59 9.59 C 5.47 8.6 6.01 8 7 8 L 17 8 C 17.99 8 18.53 8.6 18.41 9.59 L 17.19 19.81 C 17.07 20.8 16.39 21.4 15.4 21.4 L 8.6 21.4 C 7.61 21.4 6.93 20.8 6.81 19.81 Z", 0),
            ("solid", "M 5.8 6.6 L 18.2 6.6 C 18.97 6.6 19.6 7.23 19.6 8 L 19.6 8 C 19.6 8.77 18.97 9.4 18.2 9.4 L 5.8 9.4 C 5.03 9.4 4.4 8.77 4.4 8 L 4.4 8 C 4.4 7.23 5.03 6.6 5.8 6.6 Z", 0),
            ("solid", "M 10.8 18.2 C 10.8 18.86 10.26 19.4 9.6 19.4 C 8.94 19.4 8.4 18.86 8.4 18.2 C 8.4 17.54 8.94 17 9.6 17 C 10.26 17 10.8 17.54 10.8 18.2 Z", 0),
            ("solid", "M 13.6 19 C 13.6 19.66 13.06 20.2 12.4 20.2 C 11.74 20.2 11.2 19.66 11.2 19 C 11.2 18.34 11.74 17.8 12.4 17.8 C 13.06 17.8 13.6 18.34 13.6 19 Z", 0),
            ("solid", "M 15.8 17.4 C 15.8 18.06 15.26 18.6 14.6 18.6 C 13.94 18.6 13.4 18.06 13.4 17.4 C 13.4 16.74 13.94 16.2 14.6 16.2 C 15.26 16.2 15.8 16.74 15.8 17.4 Z", 0),
            ("solid", "M 12.4 15.8 C 12.4 16.46 11.86 17 11.2 17 C 10.54 17 10 16.46 10 15.8 C 10 15.14 10.54 14.6 11.2 14.6 C 11.86 14.6 12.4 15.14 12.4 15.8 Z", 0),
            ("hi", "M 7.6 11.2 L 8 14", 1.2),
        ]
        case .drinks: [
            ("soft", "M 6 3 L 18 3 C 18.4 7.8 16.6 11.6 12 11.6 C 7.4 11.6 5.6 7.8 6 3 Z", 0),
            ("solid", "M 6.4 6.4 L 17.6 6.4 C 17.2 9.4 15.4 11.6 12 11.6 C 8.6 11.6 6.8 9.4 6.4 6.4 Z", 0),
            ("solid", "M 12 11.6 L 12 19.6", 1.8),
            ("solid", "M 8.8 19 L 15.2 19 C 15.86 19 16.4 19.54 16.4 20.2 L 16.4 20.2 C 16.4 20.86 15.86 21.4 15.2 21.4 L 8.8 21.4 C 8.14 21.4 7.6 20.86 7.6 20.2 L 7.6 20.2 C 7.6 19.54 8.14 19 8.8 19 Z", 0),
            ("hi", "M 8.6 8 L 9.2 9.6", 1.1),
        ]
        case .veggies: [
            ("leaf", "M 15.6 8.4 C 14.6 5.2 15.4 2.6 17 2 C 18 3.6 17.6 6.4 15.6 8.4 Z", 0),
            ("leaf", "M 15.6 8.4 C 17.6 6.2 20.6 6 21.8 7.2 C 20.6 8.8 17.8 9.4 15.6 8.4 Z", 0),
            ("soft:FF8A3D", "M 15.2 8.8 C 17.4 10.6 16.6 13 14.8 14.8 L 6.4 21 C 5.2 21.8 3.4 20.2 4.2 19 L 10.2 10.6 C 11.8 8.4 13.6 7.6 15.2 8.8 Z", 0),
            ("solid:FF8A3D", "M 10.2 13.6 L 12 15", 1.3),
            ("solid:FF8A3D", "M 7.6 17 L 9 18.2", 1.3),
        ]
        case .bakery: [
            ("soft", "M 3.4 14 C 3.4 9 7.2 5 12 5 C 16.8 5 20.6 9 20.6 14 C 20.6 16.4 19.2 18.6 17 18.6 L 7 18.6 C 4.8 18.6 3.4 16.4 3.4 14 Z", 0),
            ("solid", "M 5.4 14.6 C 5.4 10.4 8.4 7.4 12 7.4 C 15.6 7.4 18.6 10.4 18.6 14.6 C 18.6 16.2 17.6 17.2 16.4 17.2 L 7.6 17.2 C 6.4 17.2 5.4 16.2 5.4 14.6 Z", 0),
            ("hi", "M 9 10.4 C 9.6 11.4 9.6 12.6 9 13.6", 1.3),
            ("hi", "M 12 9.6 C 12.6 10.8 12.6 12.2 12 13.4", 1.3),
            ("hi", "M 15 10.4 C 15.6 11.4 15.6 12.6 15 13.6", 1.3),
        ]
        case .hotpot: [
            ("solid", "M 8.4 2.6 C 7.4 3.8 9.4 4.8 8.4 6.4", 1.4),
            ("solid", "M 12 2 C 11 3.2 13 4.2 12 5.8", 1.4),
            ("solid", "M 15.6 2.6 C 14.6 3.8 16.6 4.8 15.6 6.4", 1.4),
            ("solid", "M 2.7 10.2 L 3.9 10.2 C 4.51 10.2 5 10.69 5 11.3 L 5 11.3 C 5 11.91 4.51 12.4 3.9 12.4 L 2.7 12.4 C 2.09 12.4 1.6 11.91 1.6 11.3 L 1.6 11.3 C 1.6 10.69 2.09 10.2 2.7 10.2 Z", 0),
            ("solid", "M 20.1 10.2 L 21.3 10.2 C 21.91 10.2 22.4 10.69 22.4 11.3 L 22.4 11.3 C 22.4 11.91 21.91 12.4 21.3 12.4 L 20.1 12.4 C 19.49 12.4 19 11.91 19 11.3 L 19 11.3 C 19 10.69 19.49 10.2 20.1 10.2 Z", 0),
            ("soft", "M 3.6 9 L 20.4 9 L 20.4 13.4 C 20.4 17.8 16.8 21 12 21 C 7.2 21 3.6 17.8 3.6 13.4 Z", 0),
            ("solid", "M 4.3 8 L 19.7 8 C 20.42 8 21 8.58 21 9.3 L 21 9.3 C 21 10.02 20.42 10.6 19.7 10.6 L 4.3 10.6 C 3.58 10.6 3 10.02 3 9.3 L 3 9.3 C 3 8.58 3.58 8 4.3 8 Z", 0),
            ("solid", "M 10.8 14.4 C 10.8 15.28 10.08 16 9.2 16 C 8.32 16 7.6 15.28 7.6 14.4 C 7.6 13.52 8.32 12.8 9.2 12.8 C 10.08 12.8 10.8 13.52 10.8 14.4 Z", 0),
            ("solid:3DBE6B", "M 16.28 13.12 C 16.51 13.74 15.85 14.55 14.81 14.93 C 13.77 15.31 12.75 15.11 12.52 14.48 C 12.29 13.86 12.95 13.05 13.99 12.67 C 15.03 12.29 16.05 12.49 16.28 13.12 Z", 0),
            ("solid", "M 13.8 17 C 13.8 17.66 13.26 18.2 12.6 18.2 C 11.94 18.2 11.4 17.66 11.4 17 C 11.4 16.34 11.94 15.8 12.6 15.8 C 13.26 15.8 13.8 16.34 13.8 17 Z", 0),
        ]
        case .taxi: [
            ("solid", "M 10 2.6 L 14 2.6 C 14.55 2.6 15 3.05 15 3.6 L 15 4.4 C 15 4.95 14.55 5.4 14 5.4 L 10 5.4 C 9.45 5.4 9 4.95 9 4.4 L 9 3.6 C 9 3.05 9.45 2.6 10 2.6 Z", 0),
            ("soft", "M 6.8 5.6 L 17.2 5.6 C 18.4 5.6 19.2 6.2 19.6 7.4 L 21 11.6 L 3 11.6 L 4.4 7.4 C 4.8 6.2 5.6 5.6 6.8 5.6 Z", 0),
            ("solid", "M 4.6 11 L 19.4 11 C 20.84 11 22 12.16 22 13.6 L 22 16 C 22 17.44 20.84 18.6 19.4 18.6 L 4.6 18.6 C 3.16 18.6 2 17.44 2 16 L 2 13.6 C 2 12.16 3.16 11 4.6 11 Z", 0),
            ("solid", "M 5 17.6 L 5.8 17.6 C 6.57 17.6 7.2 18.23 7.2 19 L 7.2 19.8 C 7.2 20.57 6.57 21.2 5.8 21.2 L 5 21.2 C 4.23 21.2 3.6 20.57 3.6 19.8 L 3.6 19 C 3.6 18.23 4.23 17.6 5 17.6 Z", 0),
            ("solid", "M 18.2 17.6 L 19 17.6 C 19.77 17.6 20.4 18.23 20.4 19 L 20.4 19.8 C 20.4 20.57 19.77 21.2 19 21.2 L 18.2 21.2 C 17.43 21.2 16.8 20.57 16.8 19.8 L 16.8 19 C 16.8 18.23 17.43 17.6 18.2 17.6 Z", 0),
            ("hi", "M 7.4 14.6 C 7.4 15.37 6.77 16 6 16 C 5.23 16 4.6 15.37 4.6 14.6 C 4.6 13.83 5.23 13.2 6 13.2 C 6.77 13.2 7.4 13.83 7.4 14.6 Z", 0),
            ("hi", "M 19.4 14.6 C 19.4 15.37 18.77 16 18 16 C 17.23 16 16.6 15.37 16.6 14.6 C 16.6 13.83 17.23 13.2 18 13.2 C 18.77 13.2 19.4 13.83 19.4 14.6 Z", 0),
            ("hi", "M 10 14.8 L 14 14.8", 1.3),
        ]
        case .metro: [
            ("solid", "M 7.4 18.6 L 5.2 22", 1.6),
            ("solid", "M 16.6 18.6 L 18.8 22", 1.6),
            ("soft", "M 9.6 2.4 L 14.4 2.4 C 17.16 2.4 19.4 4.64 19.4 7.4 L 19.4 14.4 C 19.4 17.16 17.16 19.4 14.4 19.4 L 9.6 19.4 C 6.84 19.4 4.6 17.16 4.6 14.4 L 4.6 7.4 C 4.6 4.64 6.84 2.4 9.6 2.4 Z", 0),
            ("solid", "M 8.8 5.2 L 15.2 5.2 C 16.19 5.2 17 6.01 17 7 L 17 9 C 17 9.99 16.19 10.8 15.2 10.8 L 8.8 10.8 C 7.81 10.8 7 9.99 7 9 L 7 7 C 7 6.01 7.81 5.2 8.8 5.2 Z", 0),
            ("solid", "M 10 14.6 C 10 15.37 9.37 16 8.6 16 C 7.83 16 7.2 15.37 7.2 14.6 C 7.2 13.83 7.83 13.2 8.6 13.2 C 9.37 13.2 10 13.83 10 14.6 Z", 0),
            ("solid", "M 16.8 14.6 C 16.8 15.37 16.17 16 15.4 16 C 14.63 16 14 15.37 14 14.6 C 14 13.83 14.63 13.2 15.4 13.2 C 16.17 13.2 16.8 13.83 16.8 14.6 Z", 0),
            ("hi", "M 8.6 7 L 10.4 7", 1.2),
        ]
        case .flight: [
            ("soft", "M 13.84 10.16 L 16.95 20.63 L 15.68 21.9 L 11.01 12.99 Z M 13.84 10.16 L 3.37 7.05 L 2.1 8.32 L 11.01 12.99 Z", 0),
            ("solid", "M 19.35 4.65 C 20.34 5.64 19.92 6.91 18.79 8.04 L 9.45 17.37 L 9.88 20.63 L 8.75 21.76 L 6.34 17.66 L 2.24 15.25 L 3.37 14.12 L 6.63 14.55 L 15.96 5.21 C 17.09 4.08 18.36 3.66 19.35 4.65 Z", 0),
            ("hi", "M 16.53 6.34 L 14.69 8.18", 1.1),
        ]
        case .train: [
            ("solid", "M 3 21.4 L 21 21.4", 1.6),
            ("soft", "M 6 2.6 L 18 2.6 C 19.6 2.6 20.4 3.6 20.4 5.2 L 20.4 16 C 20.4 17.6 19.4 18.6 17.8 18.6 L 6.2 18.6 C 4.6 18.6 3.6 17.6 3.6 16 L 3.6 5.2 C 3.6 3.6 4.4 2.6 6 2.6 Z", 0),
            ("solid", "M 7.4 5 L 16.6 5 C 17.48 5 18.2 5.72 18.2 6.6 L 18.2 8.8 C 18.2 9.68 17.48 10.4 16.6 10.4 L 7.4 10.4 C 6.52 10.4 5.8 9.68 5.8 8.8 L 5.8 6.6 C 5.8 5.72 6.52 5 7.4 5 Z", 0),
            ("solid", "M 3.6 12.4 L 20.4 12.4 L 20.4 14.4 L 3.6 14.4 L 3.6 12.4 Z", 0),
            ("solid", "M 8.7 16.4 C 8.7 17.01 8.21 17.5 7.6 17.5 C 6.99 17.5 6.5 17.01 6.5 16.4 C 6.5 15.79 6.99 15.3 7.6 15.3 C 8.21 15.3 8.7 15.79 8.7 16.4 Z", 0),
            ("solid", "M 17.5 16.4 C 17.5 17.01 17.01 17.5 16.4 17.5 C 15.79 17.5 15.3 17.01 15.3 16.4 C 15.3 15.79 15.79 15.3 16.4 15.3 C 17.01 15.3 17.5 15.79 17.5 16.4 Z", 0),
            ("hi", "M 7.6 6.8 L 9.4 6.8", 1.1),
        ]
        case .parking: [
            ("soft", "M 8.4 3 L 15.6 3 C 18.58 3 21 5.42 21 8.4 L 21 15.6 C 21 18.58 18.58 21 15.6 21 L 8.4 21 C 5.42 21 3 18.58 3 15.6 L 3 8.4 C 3 5.42 5.42 3 8.4 3 Z", 0),
            ("solid", "M 9.4 17.4 L 9.4 6.8 L 13 6.8 C 15 6.8 16.4 8.2 16.4 10.2 C 16.4 12.2 15 13.6 13 13.6 L 9.4 13.6", 2.4),
            ("hi", "M 5 7 C 5 6.16 5.53 5.41 6.32 5.12", 1.3),
        ]
        case .bike: [
            ("soft", "M 10 16 C 10 18.32 8.12 20.2 5.8 20.2 C 3.48 20.2 1.6 18.32 1.6 16 C 1.6 13.68 3.48 11.8 5.8 11.8 C 8.12 11.8 10 13.68 10 16 Z", 0),
            ("soft", "M 22.4 16 C 22.4 18.32 20.52 20.2 18.2 20.2 C 15.88 20.2 14 18.32 14 16 C 14 13.68 15.88 11.8 18.2 11.8 C 20.52 11.8 22.4 13.68 22.4 16 Z", 0),
            ("solid", "M 10 16 C 10 18.32 8.12 20.2 5.8 20.2 C 3.48 20.2 1.6 18.32 1.6 16 C 1.6 13.68 3.48 11.8 5.8 11.8 C 8.12 11.8 10 13.68 10 16 Z", 1.6),
            ("solid", "M 22.4 16 C 22.4 18.32 20.52 20.2 18.2 20.2 C 15.88 20.2 14 18.32 14 16 C 14 13.68 15.88 11.8 18.2 11.8 C 20.52 11.8 22.4 13.68 22.4 16 Z", 1.6),
            ("solid", "M 5.8 16 L 9.6 9 L 15.4 9 L 18.2 16", 1.7),
            ("solid", "M 9.6 9 L 12.2 16 L 15.4 9", 1.7),
            ("solid", "M 8.4 6.4 L 11 6.4", 1.8),
            ("solid", "M 15.4 9 L 14.6 6 L 17 6", 1.7),
        ]
        case .carcare: [
            ("soft", "M 5.6 8.4 C 6 7 7 6.2 8.4 6.2 L 15.6 6.2 C 17 6.2 18 7 18.4 8.4 L 19.6 12 L 4.4 12 Z", 0),
            ("solid", "M 4.8 11.4 L 19.2 11.4 C 20.53 11.4 21.6 12.47 21.6 13.8 L 21.6 15.4 C 21.6 16.73 20.53 17.8 19.2 17.8 L 4.8 17.8 C 3.47 17.8 2.4 16.73 2.4 15.4 L 2.4 13.8 C 2.4 12.47 3.47 11.4 4.8 11.4 Z", 0),
            ("solid", "M 5.4 17 L 6 17 C 6.77 17 7.4 17.63 7.4 18.4 L 7.4 19.2 C 7.4 19.97 6.77 20.6 6 20.6 L 5.4 20.6 C 4.63 20.6 4 19.97 4 19.2 L 4 18.4 C 4 17.63 4.63 17 5.4 17 Z", 0),
            ("solid", "M 18 17 L 18.6 17 C 19.37 17 20 17.63 20 18.4 L 20 19.2 C 20 19.97 19.37 20.6 18.6 20.6 L 18 20.6 C 17.23 20.6 16.6 19.97 16.6 19.2 L 16.6 18.4 C 16.6 17.63 17.23 17 18 17 Z", 0),
            ("hi", "M 7.2 14.6 C 7.2 15.26 6.66 15.8 6 15.8 C 5.34 15.8 4.8 15.26 4.8 14.6 C 4.8 13.94 5.34 13.4 6 13.4 C 6.66 13.4 7.2 13.94 7.2 14.6 Z", 0),
            ("hi", "M 19.2 14.6 C 19.2 15.26 18.66 15.8 18 15.8 C 17.34 15.8 16.8 15.26 16.8 14.6 C 16.8 13.94 17.34 13.4 18 13.4 C 18.66 13.4 19.2 13.94 19.2 14.6 Z", 0),
            ("solid:F7A21B", "M 22.8 4.6 C 22.8 6.48 21.28 8 19.4 8 C 17.52 8 16 6.48 16 4.6 C 16 2.72 17.52 1.2 19.4 1.2 C 21.28 1.2 22.8 2.72 22.8 4.6 Z", 0),
            ("hi", "M 18.2 4.6 L 20.6 4.6", 1.2),
            ("hi", "M 19.4 3.4 L 19.4 5.8", 1.2),
        ]
        case .toll: [
            ("solid", "M 4.2 4 L 5 4 C 5.88 4 6.6 4.72 6.6 5.6 L 6.6 19.8 C 6.6 20.68 5.88 21.4 5 21.4 L 4.2 21.4 C 3.32 21.4 2.6 20.68 2.6 19.8 L 2.6 5.6 C 2.6 4.72 3.32 4 4.2 4 Z", 0),
            ("soft", "M 7.6 6.6 L 20 6.6 C 20.88 6.6 21.6 7.32 21.6 8.2 L 21.6 8.2 C 21.6 9.08 20.88 9.8 20 9.8 L 7.6 9.8 C 6.72 9.8 6 9.08 6 8.2 L 6 8.2 C 6 7.32 6.72 6.6 7.6 6.6 Z", 0),
            ("solid", "M 9 6.6 L 12 6.6 L 12 9.8 L 9 9.8 L 9 6.6 Z", 0),
            ("solid", "M 15 6.6 L 18 6.6 L 18 9.8 L 15 9.8 L 15 6.6 Z", 0),
            ("solid", "M 19 16.6 C 19 18.59 17.39 20.2 15.4 20.2 C 13.41 20.2 11.8 18.59 11.8 16.6 C 11.8 14.61 13.41 13 15.4 13 C 17.39 13 19 14.61 19 16.6 Z", 0),
            ("hi", "M 15.4 15.2 C 15.67 16.33 15.67 16.33 16.8 16.6 C 15.67 16.87 15.67 16.87 15.4 18 C 15.13 16.87 15.13 16.87 14 16.6 C 15.13 16.33 15.13 16.33 15.4 15.2 Z", 0),
        ]
        case .mortgage: [
            ("soft", "M 5 10.4 L 16.6 10.4 C 16.82 10.4 17 10.58 17 10.8 L 17 18.6 C 17 19.93 15.93 21 14.6 21 L 7 21 C 5.67 21 4.6 19.93 4.6 18.6 L 4.6 10.8 C 4.6 10.58 4.78 10.4 5 10.4 Z", 0),
            ("solid", "M 9.6 4.26 C 10.35 3.6 11.25 3.6 12 4.26 L 18.4 9.94 C 19.15 10.6 18.99 11 18 11 L 3.6 11 C 2.61 11 2.45 10.6 3.2 9.94 Z", 0),
            ("solid", "M 10 14.6 L 11.6 14.6 C 12.37 14.6 13 15.23 13 16 L 13 21 L 8.6 21 L 8.6 16 C 8.6 15.23 9.23 14.6 10 14.6 Z", 0),
            ("solid:F7A21B", "M 22.6 17.2 C 22.6 19.52 20.72 21.4 18.4 21.4 C 16.08 21.4 14.2 19.52 14.2 17.2 C 14.2 14.88 16.08 13 18.4 13 C 20.72 13 22.6 14.88 22.6 17.2 Z", 0),
            ("hi", "M 18.4 15.4 L 18.4 19", 1.4),
            ("hi", "M 16.8 16.2 L 18.4 15.2 L 20 16.2", 1.2),
        ]
        case .internet: [
            ("soft", "M 5.6 13.4 L 18.4 13.4 C 19.84 13.4 21 14.56 21 16 L 21 18.2 C 21 19.64 19.84 20.8 18.4 20.8 L 5.6 20.8 C 4.16 20.8 3 19.64 3 18.2 L 3 16 C 3 14.56 4.16 13.4 5.6 13.4 Z", 0),
            ("solid", "M 8.2 17.1 C 8.2 17.76 7.66 18.3 7 18.3 C 6.34 18.3 5.8 17.76 5.8 17.1 C 5.8 16.44 6.34 15.9 7 15.9 C 7.66 15.9 8.2 16.44 8.2 17.1 Z", 0),
            ("solid", "M 11.6 17.1 C 11.6 17.76 11.06 18.3 10.4 18.3 C 9.74 18.3 9.2 17.76 9.2 17.1 C 9.2 16.44 9.74 15.9 10.4 15.9 C 11.06 15.9 11.6 16.44 11.6 17.1 Z", 0),
            ("solid", "M 15 17.1 L 18 17.1", 1.5),
            ("solid", "M 5.72 6.13 C 7.28 4.27 9.58 3.2 12 3.2 C 14.42 3.2 16.72 4.27 18.28 6.13", 1.8),
            ("solid", "M 8.46 7.86 C 10.42 5.91 13.58 5.91 15.54 7.86", 1.8),
            ("solid", "M 13.5 10.6 C 13.5 11.43 12.83 12.1 12 12.1 C 11.17 12.1 10.5 11.43 10.5 10.6 C 10.5 9.77 11.17 9.1 12 9.1 C 12.83 9.1 13.5 9.77 13.5 10.6 Z", 0),
        ]
        case .gas: [
            ("soft", "M 12 2 C 14 5.6 19.4 8.6 19.4 14.2 C 19.4 18.4 16.2 21.6 12 21.6 C 7.8 21.6 4.6 18.4 4.6 14.2 C 4.6 10.6 6.8 8.4 8.2 6.8 C 8.4 9 9.2 10.4 10.6 11 C 10.2 7.4 10.6 4.6 12 2 Z", 0),
            ("solid:4C8DF6", "M 12 11.4 C 13.4 13.6 15.4 14.8 15.4 17.2 C 15.4 19.2 13.8 20.6 12 20.6 C 10.2 20.6 8.6 19.2 8.6 17.2 C 8.6 15.2 10.6 13.8 12 11.4 Z", 0),
            ("hi", "M 11.9 17.4 C 11.9 17.9 11.5 18.3 11 18.3 C 10.5 18.3 10.1 17.9 10.1 17.4 C 10.1 16.9 10.5 16.5 11 16.5 C 11.5 16.5 11.9 16.9 11.9 17.4 Z", 0),
        ]
        case .water: [
            ("soft", "M 12 2.4 C 14.6 6.2 19 10.2 19 14.6 C 19 18.6 15.8 21.6 12 21.6 C 8.2 21.6 5 18.6 5 14.6 C 5 10.2 9.4 6.2 12 2.4 Z", 0),
            ("solid", "M 5.2 14 C 7.6 12.8 9.8 15.6 12 14.6 C 14.2 13.6 16.4 12.6 18.8 14 C 18.8 18.2 15.8 21.6 12 21.6 C 8.2 21.6 5.2 18.4 5.2 14 Z", 0),
            ("hi", "M 7.75 13.46 C 8.05 12.33 8.79 11.37 9.8 10.79", 1.3),
        ]
        case .power: [
            ("soft", "M 8.4 3 L 15.6 3 C 18.36 3 20.6 5.24 20.6 8 L 20.6 16 C 20.6 18.76 18.36 21 15.6 21 L 8.4 21 C 5.64 21 3.4 18.76 3.4 16 L 3.4 8 C 3.4 5.24 5.64 3 8.4 3 Z", 0),
            ("solid", "M 13.45 5.39 C 13.54 4.9 13.42 4.84 13.12 5.24 L 7.68 12.56 C 7.38 12.96 7.5 13.2 8 13.2 L 10.8 13.2 C 11.3 13.2 11.54 13.5 11.45 13.99 L 10.55 18.61 C 10.46 19.1 10.58 19.16 10.88 18.76 L 16.32 11.44 C 16.62 11.04 16.5 10.8 16 10.8 L 13.2 10.8 C 12.7 10.8 12.46 10.5 12.55 10.01 Z", 0),
            ("hi", "M 13.4 8.4 C 13.4 8.84 13.04 9.2 12.6 9.2 C 12.16 9.2 11.8 8.84 11.8 8.4 C 11.8 7.96 12.16 7.6 12.6 7.6 C 13.04 7.6 13.4 7.96 13.4 8.4 Z", 0),
        ]
        case .appliance: [
            ("soft", "M 7.4 2.4 L 16.6 2.4 C 18.48 2.4 20 3.92 20 5.8 L 20 18.2 C 20 20.08 18.48 21.6 16.6 21.6 L 7.4 21.6 C 5.52 21.6 4 20.08 4 18.2 L 4 5.8 C 4 3.92 5.52 2.4 7.4 2.4 Z", 0),
            ("solid", "M 6.2 2.4 L 17.8 2.4 C 19.02 2.4 20 3.38 20 4.6 L 20 6.8 L 4 6.8 L 4 4.6 C 4 3.38 4.98 2.4 6.2 2.4 Z", 0),
            ("hi", "M 7.8 4.6 C 7.8 5.04 7.44 5.4 7 5.4 C 6.56 5.4 6.2 5.04 6.2 4.6 C 6.2 4.16 6.56 3.8 7 3.8 C 7.44 3.8 7.8 4.16 7.8 4.6 Z", 0),
            ("hi", "M 10.4 4.6 C 10.4 5.04 10.04 5.4 9.6 5.4 C 9.16 5.4 8.8 5.04 8.8 4.6 C 8.8 4.16 9.16 3.8 9.6 3.8 C 10.04 3.8 10.4 4.16 10.4 4.6 Z", 0),
            ("solid", "M 17 14 C 17 16.76 14.76 19 12 19 C 9.24 19 7 16.76 7 14 C 7 11.24 9.24 9 12 9 C 14.76 9 17 11.24 17 14 Z", 0),
            ("soft:24ABEB", "M 7.4 14.4 C 9 13.2 10.6 15.6 12 14.6 C 13.4 13.6 15 13.2 16.6 14.4 C 16.4 16.8 14.4 18.6 12 18.6 C 9.6 18.6 7.6 16.8 7.4 14.4 Z", 0),
            ("hi", "M 8.99 12.91 C 9.32 12.02 10.02 11.32 10.91 10.99", 1.1),
        ]
        case .repair: [
            ("soft", "M 9.88 9.88 L 9.88 9.88 C 10.43 9.33 11.31 9.33 11.86 9.88 L 19.07 17.09 C 19.62 17.64 19.62 18.52 19.07 19.07 L 19.07 19.07 C 18.52 19.62 17.64 19.62 17.09 19.07 L 9.88 11.86 C 9.33 11.31 9.33 10.43 9.88 9.88 Z", 0),
            ("solid", "M 1.82 10.3 L 8.61 3.51 C 9.88 2.24 11.58 2.24 12.85 3.51 L 13.56 4.22 C 14.26 4.93 14.26 6.06 13.56 6.77 L 5.92 14.4 C 5.35 14.97 4.5 14.97 3.94 14.4 L 1.82 12.28 C 1.25 11.72 1.25 10.87 1.82 10.3 Z", 0),
            ("hi", "M 3.94 11.01 L 5.64 9.31", 1.1),
        ]
        case .cleaning: [
            ("solid", "M 10.8 2 L 13.2 2 C 13.97 2 14.6 2.63 14.6 3.4 L 14.6 4.8 C 14.6 5.57 13.97 6.2 13.2 6.2 L 10.8 6.2 C 10.03 6.2 9.4 5.57 9.4 4.8 L 9.4 3.4 C 9.4 2.63 10.03 2 10.8 2 Z", 0),
            ("solid", "M 14.6 3.4 L 18 3.4 L 19.4 2.4", 1.5),
            ("soft", "M 8.4 6 L 15.6 6 L 17 10 L 17 19.4 C 17 20.6 16 21.6 14.8 21.6 L 9.2 21.6 C 8 21.6 7 20.6 7 19.4 L 7 10 Z", 0),
            ("solid", "M 12 16.68 C 11.16 15.96 9.6 14.88 9.6 13.68 C 9.6 12.36 11.28 11.88 12 13.2 C 12.72 11.88 14.4 12.36 14.4 13.68 C 14.4 14.88 12.84 15.96 12 16.68 Z", 0),
            ("hi", "M 4.4 6.2 C 4.74 7.66 4.74 7.66 6.2 8 C 4.74 8.34 4.74 8.34 4.4 9.8 C 4.06 8.34 4.06 8.34 2.6 8 C 4.06 7.66 4.06 7.66 4.4 6.2 Z", 0),
            ("hi", "M 20.2 12 C 20.47 13.13 20.47 13.13 21.6 13.4 C 20.47 13.67 20.47 13.67 20.2 14.8 C 19.93 13.67 19.93 13.67 18.8 13.4 C 19.93 13.13 19.93 13.13 20.2 12 Z", 0),
            ("solid", "M 4.4 6.2 C 4.74 7.66 4.74 7.66 6.2 8 C 4.74 8.34 4.74 8.34 4.4 9.8 C 4.06 8.34 4.06 8.34 2.6 8 C 4.06 7.66 4.06 7.66 4.4 6.2 Z", 0),
            ("solid", "M 20.2 12 C 20.47 13.13 20.47 13.13 21.6 13.4 C 20.47 13.67 20.47 13.67 20.2 14.8 C 19.93 13.67 19.93 13.67 18.8 13.4 C 19.93 13.13 19.93 13.13 20.2 12 Z", 0),
        ]
        case .plants: [
            ("solid", "M 12 13 C 12 8.6 9 5.8 4.4 6 C 4.4 10.4 7.4 13.2 12 13 Z", 0),
            ("soft", "M 12 11.4 C 12 6.6 15 3.4 19.8 3.6 C 19.8 8.4 16.8 11.6 12 11.4 Z", 0),
            ("solid", "M 12 15 L 12 10.6", 1.6),
            ("solid:D9A05B", "M 5.4 14.4 L 18.6 14.4 L 17.2 20.2 C 17 21 16.4 21.6 15.6 21.6 L 8.4 21.6 C 7.6 21.6 7 21 6.8 20.2 Z", 0),
            ("hi", "M 8 16.6 L 8.4 18.6", 1.1),
        ]
        case .property: [
            ("soft", "M 4.8 7 L 10.2 7 C 11.19 7 12 7.81 12 8.8 L 12 19.6 C 12 20.59 11.19 21.4 10.2 21.4 L 4.8 21.4 C 3.81 21.4 3 20.59 3 19.6 L 3 8.8 C 3 7.81 3.81 7 4.8 7 Z", 0),
            ("solid", "M 13 2.6 L 19 2.6 C 20.1 2.6 21 3.5 21 4.6 L 21 19.4 C 21 20.5 20.1 21.4 19 21.4 L 13 21.4 C 11.9 21.4 11 20.5 11 19.4 L 11 4.6 C 11 3.5 11.9 2.6 13 2.6 Z", 0),
            ("hi", "M 13.9 5.6 L 14.9 5.6 C 15.18 5.6 15.4 5.82 15.4 6.1 L 15.4 7.1 C 15.4 7.38 15.18 7.6 14.9 7.6 L 13.9 7.6 C 13.62 7.6 13.4 7.38 13.4 7.1 L 13.4 6.1 C 13.4 5.82 13.62 5.6 13.9 5.6 Z", 0),
            ("hi", "M 17.1 5.6 L 18.1 5.6 C 18.38 5.6 18.6 5.82 18.6 6.1 L 18.6 7.1 C 18.6 7.38 18.38 7.6 18.1 7.6 L 17.1 7.6 C 16.82 7.6 16.6 7.38 16.6 7.1 L 16.6 6.1 C 16.6 5.82 16.82 5.6 17.1 5.6 Z", 0),
            ("hi", "M 13.9 9.6 L 14.9 9.6 C 15.18 9.6 15.4 9.82 15.4 10.1 L 15.4 11.1 C 15.4 11.38 15.18 11.6 14.9 11.6 L 13.9 11.6 C 13.62 11.6 13.4 11.38 13.4 11.1 L 13.4 10.1 C 13.4 9.82 13.62 9.6 13.9 9.6 Z", 0),
            ("hi", "M 17.1 9.6 L 18.1 9.6 C 18.38 9.6 18.6 9.82 18.6 10.1 L 18.6 11.1 C 18.6 11.38 18.38 11.6 18.1 11.6 L 17.1 11.6 C 16.82 11.6 16.6 11.38 16.6 11.1 L 16.6 10.1 C 16.6 9.82 16.82 9.6 17.1 9.6 Z", 0),
            ("hi", "M 13.9 13.6 L 14.9 13.6 C 15.18 13.6 15.4 13.82 15.4 14.1 L 15.4 15.1 C 15.4 15.38 15.18 15.6 14.9 15.6 L 13.9 15.6 C 13.62 15.6 13.4 15.38 13.4 15.1 L 13.4 14.1 C 13.4 13.82 13.62 13.6 13.9 13.6 Z", 0),
            ("hi", "M 17.1 13.6 L 18.1 13.6 C 18.38 13.6 18.6 13.82 18.6 14.1 L 18.6 15.1 C 18.6 15.38 18.38 15.6 18.1 15.6 L 17.1 15.6 C 16.82 15.6 16.6 15.38 16.6 15.1 L 16.6 14.1 C 16.6 13.82 16.82 13.6 17.1 13.6 Z", 0),
            ("solid", "M 5.5 10 L 6.5 10 C 6.78 10 7 10.22 7 10.5 L 7 11.5 C 7 11.78 6.78 12 6.5 12 L 5.5 12 C 5.22 12 5 11.78 5 11.5 L 5 10.5 C 5 10.22 5.22 10 5.5 10 Z", 0),
            ("solid", "M 5.5 14 L 6.5 14 C 6.78 14 7 14.22 7 14.5 L 7 15.5 C 7 15.78 6.78 16 6.5 16 L 5.5 16 C 5.22 16 5 15.78 5 15.5 L 5 14.5 C 5 14.22 5.22 14 5.5 14 Z", 0),
        ]
        case .cosmetics: [
            ("solid", "M 9 2.6 L 14.6 4.8 L 14.6 10 L 9 10 Z", 0),
            ("soft", "M 8.8 9.4 L 15.2 9.4 C 15.75 9.4 16.2 9.85 16.2 10.4 L 16.2 11.6 C 16.2 12.15 15.75 12.6 15.2 12.6 L 8.8 12.6 C 8.25 12.6 7.8 12.15 7.8 11.6 L 7.8 10.4 C 7.8 9.85 8.25 9.4 8.8 9.4 Z", 0),
            ("solid", "M 9.2 12 L 14.8 12 C 16.02 12 17 12.98 17 14.2 L 17 19.4 C 17 20.62 16.02 21.6 14.8 21.6 L 9.2 21.6 C 7.98 21.6 7 20.62 7 19.4 L 7 14.2 C 7 12.98 7.98 12 9.2 12 Z", 0),
            ("hi", "M 9.2 14.4 L 9.2 18.6", 1.3),
        ]
        case .shoes: [
            ("soft", "M 3.2 5.6 L 8.8 5.6 C 9.6 8 11 9.4 13.4 10 L 18 11.2 C 20.4 11.8 21.6 13.4 21.6 15.6 L 21.6 16.4 L 2.6 16.4 L 2.6 6.2 C 2.6 5.8 2.8 5.6 3.2 5.6 Z", 0),
            ("solid", "M 4.2 16 L 20 16 C 20.88 16 21.6 16.72 21.6 17.6 L 21.6 18 C 21.6 18.88 20.88 19.6 20 19.6 L 4.2 19.6 C 3.32 19.6 2.6 18.88 2.6 18 L 2.6 17.6 C 2.6 16.72 3.32 16 4.2 16 Z", 0),
            ("solid", "M 10 11.4 L 11.6 9.6", 1.3),
            ("solid", "M 12.4 12.4 L 14 10.6", 1.3),
            ("hi", "M 6 12.33 C 5.51 11.91 4.6 11.28 4.6 10.58 C 4.6 9.81 5.58 9.53 6 10.3 C 6.42 9.53 7.4 9.81 7.4 10.58 C 7.4 11.28 6.49 11.91 6 12.33 Z", 0),
        ]
        case .handbag: [
            ("solid", "M 7.6 10 C 7.6 5.6 9.4 3.4 12 3.4 C 14.6 3.4 16.4 5.6 16.4 10", 1.8),
            ("soft", "M 5.4 9 L 18.6 9 C 19.6 9 20.4 9.8 20.6 10.8 L 21.4 18.6 C 21.6 20.2 20.4 21.4 18.8 21.4 L 5.2 21.4 C 3.6 21.4 2.4 20.2 2.6 18.6 L 3.4 10.8 C 3.6 9.8 4.4 9 5.4 9 Z", 0),
            ("solid", "M 2.8 12.6 L 21.2 12.6 L 21.2 15 L 2.8 15 L 2.8 12.6 Z", 0),
            ("solid", "M 11.4 11.6 L 12.6 11.6 C 13.26 11.6 13.8 12.14 13.8 12.8 L 13.8 14.8 C 13.8 15.46 13.26 16 12.6 16 L 11.4 16 C 10.74 16 10.2 15.46 10.2 14.8 L 10.2 12.8 C 10.2 12.14 10.74 11.6 11.4 11.6 Z", 0),
            ("hi", "M 12.8 13.8 C 12.8 14.24 12.44 14.6 12 14.6 C 11.56 14.6 11.2 14.24 11.2 13.8 C 11.2 13.36 11.56 13 12 13 C 12.44 13 12.8 13.36 12.8 13.8 Z", 0),
        ]
        case .jewelry: [
            ("solid", "M 7 4.4 C 7.37 3.9 7.98 3.6 8.6 3.6 L 15.4 3.6 C 16.02 3.6 16.63 3.9 17 4.4 L 18.8 6.8 C 19.17 7.3 19.09 7.81 18.57 8.16 L 12.83 12.04 C 12.31 12.39 11.69 12.39 11.17 12.04 L 5.43 8.16 C 4.91 7.81 4.83 7.3 5.2 6.8 Z", 0),
            ("hi", "M 9.56 4.97 C 9.46 4.74 9.55 4.6 9.8 4.6 L 11.6 4.6 C 11.85 4.6 11.93 4.74 11.82 4.96 L 10.78 7.04 C 10.67 7.26 10.54 7.26 10.44 7.03 Z", 0),
            ("soft:F7A21B", "M 17.6 16 C 17.6 19.09 15.09 21.6 12 21.6 C 8.91 21.6 6.4 19.09 6.4 16 C 6.4 12.91 8.91 10.4 12 10.4 C 15.09 10.4 17.6 12.91 17.6 16 Z", 0),
            ("solid:F7A21B", "M 17.6 16 C 17.6 19.09 15.09 21.6 12 21.6 C 8.91 21.6 6.4 19.09 6.4 16 C 6.4 12.91 8.91 10.4 12 10.4 C 15.09 10.4 17.6 12.91 17.6 16 Z", 1.8),
        ]
        case .glasses: [
            ("soft", "M 11 13.4 C 11 15.83 9.03 17.8 6.6 17.8 C 4.17 17.8 2.2 15.83 2.2 13.4 C 2.2 10.97 4.17 9 6.6 9 C 9.03 9 11 10.97 11 13.4 Z", 0),
            ("soft", "M 21.8 13.4 C 21.8 15.83 19.83 17.8 17.4 17.8 C 14.97 17.8 13 15.83 13 13.4 C 13 10.97 14.97 9 17.4 9 C 19.83 9 21.8 10.97 21.8 13.4 Z", 0),
            ("solid", "M 11 13.4 C 11 15.83 9.03 17.8 6.6 17.8 C 4.17 17.8 2.2 15.83 2.2 13.4 C 2.2 10.97 4.17 9 6.6 9 C 9.03 9 11 10.97 11 13.4 Z", 1.8),
            ("solid", "M 21.8 13.4 C 21.8 15.83 19.83 17.8 17.4 17.8 C 14.97 17.8 13 15.83 13 13.4 C 13 10.97 14.97 9 17.4 9 C 19.83 9 21.8 10.97 21.8 13.4 Z", 1.8),
            ("solid", "M 11 12.6 C 11.6 11.6 12.4 11.6 13 12.6", 1.7),
            ("solid", "M 2.2 12.4 L 1.6 8.4", 1.6),
            ("solid", "M 21.8 12.4 L 22.4 8.4", 1.6),
            ("hi", "M 4.34 12.58 C 4.59 11.91 5.11 11.39 5.78 11.14", 1.1),
            ("hi", "M 15.14 12.58 C 15.39 11.91 15.91 11.39 16.58 11.14", 1.1),
        ]
        case .books: [
            ("soft:F2667A", "M 4.6 15.6 L 19.4 15.6 C 20.28 15.6 21 16.32 21 17.2 L 21 19.4 C 21 20.28 20.28 21 19.4 21 L 4.6 21 C 3.72 21 3 20.28 3 19.4 L 3 17.2 C 3 16.32 3.72 15.6 4.6 15.6 Z", 0),
            ("solid:F2667A", "M 4.5 15.6 L 6 15.6 L 6 21 L 4.5 21 C 3.67 21 3 20.33 3 19.5 L 3 17.1 C 3 16.27 3.67 15.6 4.5 15.6 Z", 0),
            ("soft", "M 6.03 10.05 L 18.8 9.16 C 19.68 9.1 20.44 9.76 20.5 10.64 L 20.66 12.84 C 20.72 13.72 20.05 14.49 19.17 14.55 L 6.4 15.44 C 5.52 15.5 4.76 14.84 4.7 13.96 L 4.54 11.76 C 4.48 10.88 5.15 10.11 6.03 10.05 Z", 0),
            ("solid", "M 5.71 9.81 L 7.21 9.7 L 7.58 15.09 L 6.09 15.19 C 5.26 15.25 4.55 14.63 4.49 13.8 L 4.32 11.41 C 4.26 10.58 4.89 9.86 5.71 9.81 Z", 0),
            ("solid:2DB884", "M 7.75 3.34 L 17.93 3.87 C 18.82 3.92 19.49 4.67 19.45 5.55 L 19.33 7.75 C 19.29 8.63 18.53 9.31 17.65 9.26 L 7.47 8.73 C 6.58 8.68 5.91 7.93 5.95 7.05 L 6.07 4.85 C 6.11 3.97 6.87 3.29 7.75 3.34 Z", 0),
            ("hi", "M 10 6.2 L 16 6.4", 1.2),
        ]
        case .stationery: [
            ("soft:4C8DF6", "M 4.2 15 L 19.8 15 C 20.68 15 21.4 15.72 21.4 16.6 L 21.4 19 C 21.4 19.88 20.68 20.6 19.8 20.6 L 4.2 20.6 C 3.32 20.6 2.6 19.88 2.6 19 L 2.6 16.6 C 2.6 15.72 3.32 15 4.2 15 Z", 0),
            ("solid:4C8DF6", "M 6 15 L 6 17.4", 1.2),
            ("solid:4C8DF6", "M 9.6 15 L 9.6 16.6", 1.2),
            ("solid:4C8DF6", "M 13.2 15 L 13.2 17.4", 1.2),
            ("solid:4C8DF6", "M 16.8 15 L 16.8 16.6", 1.2),
            ("soft", "M 4.48 3.35 L 6.44 1.97 C 6.72 1.78 7.09 1.85 7.28 2.12 L 13.47 10.97 C 13.66 11.24 13.6 11.61 13.33 11.8 L 11.36 13.18 C 11.09 13.37 10.72 13.3 10.53 13.03 L 4.33 4.19 C 4.14 3.91 4.21 3.54 4.48 3.35 Z", 0),
            ("solid", "M 11.3 13.62 C 10.96 13.46 10.94 13.23 11.25 13.02 L 13.21 11.64 C 13.52 11.43 13.73 11.52 13.76 11.89 L 14.01 14.35 C 14.04 14.72 13.86 14.85 13.52 14.69 Z", 0),
            ("solid", "M 4.97 3.01 L 5.95 2.32 C 6.5 1.94 7.24 2.07 7.62 2.61 L 8.43 3.76 L 5.48 5.82 L 4.68 4.68 C 4.29 4.13 4.43 3.39 4.97 3.01 Z", 0),
        ]
        case .toys: [
            ("solid", "M 9.2 5.8 C 9.2 7.35 7.95 8.6 6.4 8.6 C 4.85 8.6 3.6 7.35 3.6 5.8 C 3.6 4.25 4.85 3 6.4 3 C 7.95 3 9.2 4.25 9.2 5.8 Z", 0),
            ("solid", "M 20.4 5.8 C 20.4 7.35 19.15 8.6 17.6 8.6 C 16.05 8.6 14.8 7.35 14.8 5.8 C 14.8 4.25 16.05 3 17.6 3 C 19.15 3 20.4 4.25 20.4 5.8 Z", 0),
            ("soft", "M 19 11 C 19 14.87 15.87 18 12 18 C 8.13 18 5 14.87 5 11 C 5 7.13 8.13 4 12 4 C 15.87 4 19 7.13 19 11 Z", 0),
            ("soft", "M 17.6 19 C 17.6 20.88 15.09 22.4 12 22.4 C 8.91 22.4 6.4 20.88 6.4 19 C 6.4 17.12 8.91 15.6 12 15.6 C 15.09 15.6 17.6 17.12 17.6 19 Z", 0),
            ("solid", "M 14.8 13 C 14.8 14.22 13.55 15.2 12 15.2 C 10.45 15.2 9.2 14.22 9.2 13 C 9.2 11.78 10.45 10.8 12 10.8 C 13.55 10.8 14.8 11.78 14.8 13 Z", 0),
            ("ink", "M 10.4 9.8 C 10.4 10.35 9.95 10.8 9.4 10.8 C 8.85 10.8 8.4 10.35 8.4 9.8 C 8.4 9.25 8.85 8.8 9.4 8.8 C 9.95 8.8 10.4 9.25 10.4 9.8 Z", 0),
            ("ink", "M 15.6 9.8 C 15.6 10.35 15.15 10.8 14.6 10.8 C 14.05 10.8 13.6 10.35 13.6 9.8 C 13.6 9.25 14.05 8.8 14.6 8.8 C 15.15 8.8 15.6 9.25 15.6 9.8 Z", 0),
            ("ink", "M 12.8 12.4 C 12.8 12.84 12.44 13.2 12 13.2 C 11.56 13.2 11.2 12.84 11.2 12.4 C 11.2 11.96 11.56 11.6 12 11.6 C 12.44 11.6 12.8 11.96 12.8 12.4 Z", 0),
        ]
        case .online: [
            ("soft", "M 10.56 3.3 C 11.45 2.87 12.55 2.87 13.44 3.3 L 19.56 6.3 C 20.45 6.73 21 7.61 21 8.6 L 21 15.4 C 21 16.39 20.45 17.27 19.56 17.7 L 13.44 20.7 C 12.55 21.13 11.45 21.13 10.56 20.7 L 4.44 17.7 C 3.55 17.27 3 16.39 3 15.4 L 3 8.6 C 3 7.61 3.55 6.73 4.44 6.3 Z", 0),
            ("solid", "M 3 8.4 C 3 7.53 3.48 7.23 4.26 7.61 L 10.74 10.79 C 11.52 11.17 12 11.93 12 12.8 L 12 20 C 12 20.87 11.52 21.17 10.74 20.79 L 4.26 17.61 C 3.48 17.23 3 16.47 3 15.6 Z", 0),
            ("solid", "M 7.4 4.8 L 16.4 9.2 L 16.4 12.6", 1.6),
            ("hi", "M 7.4 15.72 C 6.84 15.24 5.8 14.52 5.8 13.72 C 5.8 12.84 6.92 12.52 7.4 13.4 C 7.88 12.52 9 12.84 9 13.72 C 9 14.52 7.96 15.24 7.4 15.72 Z", 0),
        ]
        case .dental: [
            ("soft", "M 7.6 3 C 9.4 3 10.4 4 12 4 C 13.6 4 14.6 3 16.4 3 C 19.4 3 20.8 5.6 20.4 9 C 20 12 18.8 13.6 18.2 16.6 C 17.6 19.6 17 21.4 15.6 21.4 C 14 21.4 13.8 18.6 13.4 16.6 C 13.2 15.6 12.8 15 12 15 C 11.2 15 10.8 15.6 10.6 16.6 C 10.2 18.6 10 21.4 8.4 21.4 C 7 21.4 6.4 19.6 5.8 16.6 C 5.2 13.6 4 12 3.6 9 C 3.2 5.6 4.6 3 7.6 3 Z", 0),
            ("hi", "M 16 6.2 C 16.42 7.98 16.42 7.98 18.2 8.4 C 16.42 8.82 16.42 8.82 16 10.6 C 15.58 8.82 15.58 8.82 13.8 8.4 C 15.58 7.98 15.58 7.98 16 6.2 Z", 0),
            ("hi", "M 6.4 6.6 C 7 5.8 8 5.6 8.8 5.8", 1.3),
            ("solid", "M 16 6.2 C 16.42 7.98 16.42 7.98 18.2 8.4 C 16.42 8.82 16.42 8.82 16 10.6 C 15.58 8.82 15.58 8.82 13.8 8.4 C 15.58 7.98 15.58 7.98 16 6.2 Z", 0),
        ]
        case .pharmacy: [
            ("solid", "M 7.6 2.4 L 16.4 2.4 C 17.28 2.4 18 3.12 18 4 L 18 4.8 C 18 5.68 17.28 6.4 16.4 6.4 L 7.6 6.4 C 6.72 6.4 6 5.68 6 4.8 L 6 4 C 6 3.12 6.72 2.4 7.6 2.4 Z", 0),
            ("soft", "M 8 5.6 L 16 5.6 C 17.88 5.6 19.4 7.12 19.4 9 L 19.4 18.2 C 19.4 20.08 17.88 21.6 16 21.6 L 8 21.6 C 6.12 21.6 4.6 20.08 4.6 18.2 L 4.6 9 C 4.6 7.12 6.12 5.6 8 5.6 Z", 0),
            ("solid", "M 11.8 9.6 L 12.2 9.6 C 12.86 9.6 13.4 10.14 13.4 10.8 L 13.4 16.8 C 13.4 17.46 12.86 18 12.2 18 L 11.8 18 C 11.14 18 10.6 17.46 10.6 16.8 L 10.6 10.8 C 10.6 10.14 11.14 9.6 11.8 9.6 Z", 0),
            ("solid", "M 9 12.4 L 15 12.4 C 15.66 12.4 16.2 12.94 16.2 13.6 L 16.2 14 C 16.2 14.66 15.66 15.2 15 15.2 L 9 15.2 C 8.34 15.2 7.8 14.66 7.8 14 L 7.8 13.6 C 7.8 12.94 8.34 12.4 9 12.4 Z", 0),
            ("hi", "M 6.4 9.2 C 6.4 8.53 6.82 7.93 7.45 7.7", 1.3),
        ]
        case .checkup: [
            ("soft", "M 12 20.33 C 8.71 17.51 2.6 13.28 2.6 8.58 C 2.6 3.41 9.18 1.53 12 6.7 C 14.82 1.53 21.4 3.41 21.4 8.58 C 21.4 13.28 15.29 17.51 12 20.33 Z", 0),
            ("solid", "M 3.4 12 L 8 12 L 9.6 8.6 L 12.4 16 L 14.4 10.4 L 15.6 12 L 20.6 12", 1.9),
        ]
        case .skincare: [
            ("solid", "M 6.4 6 L 17.6 6 C 18.59 6 19.4 6.81 19.4 7.8 L 19.4 8.6 C 19.4 9.59 18.59 10.4 17.6 10.4 L 6.4 10.4 C 5.41 10.4 4.6 9.59 4.6 8.6 L 4.6 7.8 C 4.6 6.81 5.41 6 6.4 6 Z", 0),
            ("soft", "M 4 10 L 20 10 L 20 17.4 C 20 19.6 18.4 21.2 16.2 21.2 L 7.8 21.2 C 5.6 21.2 4 19.6 4 17.4 Z", 0),
            ("hi", "M 12 17.29 C 11.23 16.63 9.8 15.64 9.8 14.54 C 9.8 13.33 11.34 12.89 12 14.1 C 12.66 12.89 14.2 13.33 14.2 14.54 C 14.2 15.64 12.77 16.63 12 17.29 Z", 0),
            ("solid", "M 18.6 0.8 C 18.98 2.42 18.98 2.42 20.6 2.8 C 18.98 3.18 18.98 3.18 18.6 4.8 C 18.22 3.18 18.22 3.18 16.6 2.8 C 18.22 2.42 18.22 2.42 18.6 0.8 Z", 0),
            ("solid", "M 15 1 C 15.23 1.97 15.23 1.97 16.2 2.2 C 15.23 2.43 15.23 2.43 15 3.4 C 14.77 2.43 14.77 2.43 13.8 2.2 C 14.77 1.97 14.77 1.97 15 1 Z", 0),
        ]
        case .haircut: [
            ("soft", "M 10 17.4 C 10 19.28 8.48 20.8 6.6 20.8 C 4.72 20.8 3.2 19.28 3.2 17.4 C 3.2 15.52 4.72 14 6.6 14 C 8.48 14 10 15.52 10 17.4 Z", 0),
            ("soft", "M 20.8 17.4 C 20.8 19.28 19.28 20.8 17.4 20.8 C 15.52 20.8 14 19.28 14 17.4 C 14 15.52 15.52 14 17.4 14 C 19.28 14 20.8 15.52 20.8 17.4 Z", 0),
            ("solid", "M 10 17.4 C 10 19.28 8.48 20.8 6.6 20.8 C 4.72 20.8 3.2 19.28 3.2 17.4 C 3.2 15.52 4.72 14 6.6 14 C 8.48 14 10 15.52 10 17.4 Z", 1.8),
            ("solid", "M 20.8 17.4 C 20.8 19.28 19.28 20.8 17.4 20.8 C 15.52 20.8 14 19.28 14 17.4 C 14 15.52 15.52 14 17.4 14 C 19.28 14 20.8 15.52 20.8 17.4 Z", 1.8),
            ("solid", "M 8.8 14.6 L 15.4 2.6 C 15.8 2 16.6 2.2 16.6 2.8 L 10.6 15.8 Z", 0),
            ("solid", "M 15.2 14.6 L 8.6 2.6 C 8.2 2 7.4 2.2 7.4 2.8 L 13.4 15.8 Z", 0),
            ("hi", "M 13 10 C 13 10.55 12.55 11 12 11 C 11.45 11 11 10.55 11 10 C 11 9.45 11.45 9 12 9 C 12.55 9 13 9.45 13 10 Z", 0),
        ]
        case .spa: [
            ("soft", "M 12 20.6 C 7 20.6 2.6 17.6 2.4 12.4 C 5.6 12 9 13.8 12 17 C 15 13.8 18.4 12 21.6 12.4 C 21.4 17.6 17 20.6 12 20.6 Z", 0),
            ("solid", "M 12 17.4 C 9.4 15 8.4 11.8 8.6 8.6 C 8.8 6.4 10 4.4 12 3 C 14 4.4 15.2 6.4 15.4 8.6 C 15.6 11.8 14.6 15 12 17.4 Z", 0),
            ("hi", "M 11 7 L 10.6 9.6", 1.1),
        ]
        case .gym: [
            ("soft", "M 12 21 C 6.4 21 3 17.4 3 13 C 3 9.8 4.8 7.6 6.6 6.4 C 7.2 8.6 8.4 9.4 9.6 9.4 C 9.4 6.4 10.6 3.8 13 2.4 C 13.2 5.4 15.6 6.4 17.6 8.6 C 19.6 10.6 21 12.4 21 14.4 C 21 18.4 17.4 21 12 21 Z", 0),
            ("solid", "M 7.7 13 L 16.3 13 C 16.91 13 17.4 13.49 17.4 14.1 L 17.4 14.1 C 17.4 14.71 16.91 15.2 16.3 15.2 L 7.7 15.2 C 7.09 15.2 6.6 14.71 6.6 14.1 L 6.6 14.1 C 6.6 13.49 7.09 13 7.7 13 Z", 0),
            ("solid", "M 6.2 11 L 6.4 11 C 7.06 11 7.6 11.54 7.6 12.2 L 7.6 16 C 7.6 16.66 7.06 17.2 6.4 17.2 L 6.2 17.2 C 5.54 17.2 5 16.66 5 16 L 5 12.2 C 5 11.54 5.54 11 6.2 11 Z", 0),
            ("solid", "M 17.6 11 L 17.8 11 C 18.46 11 19 11.54 19 12.2 L 19 16 C 19 16.66 18.46 17.2 17.8 17.2 L 17.6 17.2 C 16.94 17.2 16.4 16.66 16.4 16 L 16.4 12.2 C 16.4 11.54 16.94 11 17.6 11 Z", 0),
        ]
        case .movie: [
            ("soft", "M 7 9 C 5 9 4 7.2 4.8 5.6 C 5.4 4.2 7 3.8 8 4.4 C 8.4 2.8 10 2 11.4 2.6 C 12.4 1.8 14 2 14.8 3 C 16.2 2.4 17.8 3.4 17.8 5 C 19.4 5 20.4 6.8 19.4 8.2 C 19 8.8 18.4 9 17 9 Z", 0),
            ("solid", "M 5 8.4 L 19 8.4 L 17.4 21.2 L 6.6 21.2 Z", 0),
            ("hi", "M 8.2 8.4 L 10.4 8.4 L 10.4 21.2 L 8.2 21.2 L 8.2 8.4 Z", 0),
            ("hi", "M 13.6 8.4 L 15.8 8.4 L 15.8 21.2 L 13.6 21.2 L 13.6 8.4 Z", 0),
        ]
        case .music: [
            ("soft", "M 9.79 16.84 C 10.32 18.29 9.32 19.99 7.56 20.63 C 5.79 21.27 3.93 20.62 3.41 19.16 C 2.88 17.71 3.88 16.01 5.64 15.37 C 7.41 14.73 9.27 15.38 9.79 16.84 Z", 0),
            ("soft", "M 20.19 14.44 C 20.72 15.89 19.72 17.59 17.96 18.23 C 16.19 18.87 14.33 18.22 13.81 16.76 C 13.28 15.31 14.28 13.61 16.04 12.97 C 17.81 12.33 19.67 12.98 20.19 14.44 Z", 0),
            ("solid", "M 9.79 16.84 C 10.32 18.29 9.32 19.99 7.56 20.63 C 5.79 21.27 3.93 20.62 3.41 19.16 C 2.88 17.71 3.88 16.01 5.64 15.37 C 7.41 14.73 9.27 15.38 9.79 16.84 Z", 0),
            ("solid", "M 20.19 14.44 C 20.72 15.89 19.72 17.59 17.96 18.23 C 16.19 18.87 14.33 18.22 13.81 16.76 C 13.28 15.31 14.28 13.61 16.04 12.97 C 17.81 12.33 19.67 12.98 20.19 14.44 Z", 0),
            ("solid", "M 9.6 17.2 L 9.6 5.6 L 20 3.2 L 20 14.8", 2),
            ("solid", "M 9.6 9.2 L 20 6.8", 2),
            ("hi", "M 6.4 17.2 C 6.4 17.64 6.04 18 5.6 18 C 5.16 18 4.8 17.64 4.8 17.2 C 4.8 16.76 5.16 16.4 5.6 16.4 C 6.04 16.4 6.4 16.76 6.4 17.2 Z", 0),
            ("hi", "M 16.8 14.8 C 16.8 15.24 16.44 15.6 16 15.6 C 15.56 15.6 15.2 15.24 15.2 14.8 C 15.2 14.36 15.56 14 16 14 C 16.44 14 16.8 14.36 16.8 14.8 Z", 0),
        ]
        case .ticket: [
            ("soft", "M 3.19 7.12 L 18.06 3.96 C 19.04 3.76 19.99 4.37 20.2 5.35 L 20.7 7.7 C 19.33 7.99 18.56 9.18 18.85 10.54 C 19.14 11.91 20.32 12.68 21.69 12.39 L 22.19 14.74 C 22.4 15.72 21.78 16.67 20.81 16.88 L 5.94 20.04 C 4.96 20.24 4.01 19.63 3.8 18.65 L 3.3 16.3 C 4.67 16.01 5.44 14.82 5.15 13.46 C 4.86 12.09 3.68 11.32 2.31 11.61 L 1.81 9.26 C 1.6 8.28 2.22 7.33 3.19 7.12 Z", 0),
            ("solid", "M 11 8.77 C 11.1 8.35 11.33 8.3 11.6 8.64 L 12.38 9.62 C 12.65 9.96 13.08 10.16 13.51 10.13 L 14.77 10.05 C 15.2 10.02 15.32 10.22 15.08 10.58 L 14.38 11.63 C 14.14 11.99 14.09 12.46 14.25 12.86 L 14.71 14.03 C 14.87 14.43 14.72 14.6 14.3 14.49 L 13.09 14.15 C 12.67 14.03 12.21 14.13 11.88 14.4 L 10.91 15.21 C 10.58 15.48 10.36 15.39 10.35 14.95 L 10.3 13.7 C 10.28 13.27 10.04 12.86 9.68 12.63 L 8.61 11.96 C 8.25 11.72 8.27 11.49 8.68 11.34 L 9.86 10.9 C 10.26 10.75 10.58 10.4 10.69 9.98 Z", 0),
            ("hi", "M 16 7.4 L 17.2 15.4", 1.2),
        ]
        case .camera: [
            ("solid", "M 9.4 3.6 L 14.6 3.6 C 15.37 3.6 16 4.23 16 5 L 16 5.8 C 16 6.57 15.37 7.2 14.6 7.2 L 9.4 7.2 C 8.63 7.2 8 6.57 8 5.8 L 8 5 C 8 4.23 8.63 3.6 9.4 3.6 Z", 0),
            ("soft", "M 6 6 L 18 6 C 19.99 6 21.6 7.61 21.6 9.6 L 21.6 16.8 C 21.6 18.79 19.99 20.4 18 20.4 L 6 20.4 C 4.01 20.4 2.4 18.79 2.4 16.8 L 2.4 9.6 C 2.4 7.61 4.01 6 6 6 Z", 0),
            ("solid", "M 16.8 13.2 C 16.8 15.85 14.65 18 12 18 C 9.35 18 7.2 15.85 7.2 13.2 C 7.2 10.55 9.35 8.4 12 8.4 C 14.65 8.4 16.8 10.55 16.8 13.2 Z", 0),
            ("soft", "M 14.6 13.2 C 14.6 14.64 13.44 15.8 12 15.8 C 10.56 15.8 9.4 14.64 9.4 13.2 C 9.4 11.76 10.56 10.6 12 10.6 C 13.44 10.6 14.6 11.76 14.6 13.2 Z", 0),
            ("hi", "M 11.7 12 C 11.7 12.5 11.3 12.9 10.8 12.9 C 10.3 12.9 9.9 12.5 9.9 12 C 9.9 11.5 10.3 11.1 10.8 11.1 C 11.3 11.1 11.7 11.5 11.7 12 Z", 0),
            ("solid", "M 19 9.4 C 19 9.95 18.55 10.4 18 10.4 C 17.45 10.4 17 9.95 17 9.4 C 17 8.85 17.45 8.4 18 8.4 C 18.55 8.4 19 8.85 19 9.4 Z", 0),
        ]
        case .bar: [
            ("soft", "M 3.97 5.01 C 3.37 4.38 3.53 4 4.4 4 L 19.6 4 C 20.47 4 20.63 4.38 20.03 5.01 L 12.97 12.39 C 12.37 13.02 11.63 13.02 11.03 12.39 Z", 0),
            ("solid", "M 7.08 8.13 C 6.66 7.68 6.78 7.4 7.4 7.4 L 16.6 7.4 C 17.22 7.4 17.34 7.68 16.92 8.13 L 12.68 12.67 C 12.26 13.12 11.74 13.12 11.32 12.67 Z", 0),
            ("solid", "M 12 13 L 12 20", 1.8),
            ("solid", "M 8.7 19.4 L 15.3 19.4 C 15.91 19.4 16.4 19.89 16.4 20.5 L 16.4 20.5 C 16.4 21.11 15.91 21.6 15.3 21.6 L 8.7 21.6 C 8.09 21.6 7.6 21.11 7.6 20.5 L 7.6 20.5 C 7.6 19.89 8.09 19.4 8.7 19.4 Z", 0),
            ("solid:3DBE6B", "M 19.6 3.6 C 19.6 4.82 18.62 5.8 17.4 5.8 C 16.18 5.8 15.2 4.82 15.2 3.6 C 15.2 2.38 16.18 1.4 17.4 1.4 C 18.62 1.4 19.6 2.38 19.6 3.6 Z", 0),
            ("solid", "M 14.6 1.6 L 17.4 3.6", 1.2),
        ]
        case .karaoke: [
            ("soft", "M 9.79 12.33 L 13.06 10.03 L 18.15 18.68 C 18.41 19.23 18.23 19.85 17.74 20.19 C 17.24 20.54 16.61 20.49 16.18 20.06 Z", 0),
            ("solid", "M 12.72 4.66 C 14.24 6.83 13.71 9.82 11.54 11.34 C 9.37 12.87 6.38 12.34 4.86 10.17 C 3.34 7.99 3.86 5 6.03 3.48 C 8.21 1.96 11.2 2.49 12.72 4.66 Z", 0),
            ("hi", "M 5.89 8.19 C 5.66 7.33 5.82 6.42 6.33 5.69", 1.2),
            ("solid", "M 19.6 11.4 C 19.98 13.02 19.98 13.02 21.6 13.4 C 19.98 13.78 19.98 13.78 19.6 15.4 C 19.22 13.78 19.22 13.78 17.6 13.4 C 19.22 13.02 19.22 13.02 19.6 11.4 Z", 0),
            ("solid", "M 4.6 2.2 C 4.87 3.33 4.87 3.33 6 3.6 C 4.87 3.87 4.87 3.87 4.6 5 C 4.33 3.87 4.33 3.87 3.2 3.6 C 4.33 3.33 4.33 3.33 4.6 2.2 Z", 0),
        ]
        case .hobby: [
            ("soft", "M 12 2.6 C 17.6 2.6 21.4 6.4 21.4 11 C 21.4 14 19.2 15 17.4 14.4 C 15.8 13.8 14.4 14.6 14.4 16.4 C 14.4 18 15.4 18.6 15.4 19.8 C 15.4 21 14 21.4 12 21.4 C 6.6 21.4 2.6 17.2 2.6 12 C 2.6 6.8 6.6 2.6 12 2.6 Z", 0),
            ("solid:F2556B", "M 9.4 10.4 C 9.4 11.39 8.59 12.2 7.6 12.2 C 6.61 12.2 5.8 11.39 5.8 10.4 C 5.8 9.41 6.61 8.6 7.6 8.6 C 8.59 8.6 9.4 9.41 9.4 10.4 Z", 0),
            ("solid:F5B300", "M 13.4 6.8 C 13.4 7.79 12.59 8.6 11.6 8.6 C 10.61 8.6 9.8 7.79 9.8 6.8 C 9.8 5.81 10.61 5 11.6 5 C 12.59 5 13.4 5.81 13.4 6.8 Z", 0),
            ("solid:4C8DF6", "M 18.2 8.2 C 18.2 9.19 17.39 10 16.4 10 C 15.41 10 14.6 9.19 14.6 8.2 C 14.6 7.21 15.41 6.4 16.4 6.4 C 17.39 6.4 18.2 7.21 18.2 8.2 Z", 0),
            ("solid:3DBE6B", "M 9.4 15.6 C 9.4 16.59 8.59 17.4 7.6 17.4 C 6.61 17.4 5.8 16.59 5.8 15.6 C 5.8 14.61 6.61 13.8 7.6 13.8 C 8.59 13.8 9.4 14.61 9.4 15.6 Z", 0),
        ]
        case .hotel: [
            ("soft", "M 4.6 10.6 L 19.4 10.6 C 20.5 10.6 21.4 11.5 21.4 12.6 L 21.4 15.4 C 21.4 16.5 20.5 17.4 19.4 17.4 L 4.6 17.4 C 3.5 17.4 2.6 16.5 2.6 15.4 L 2.6 12.6 C 2.6 11.5 3.5 10.6 4.6 10.6 Z", 0),
            ("solid", "M 3.8 4 L 4 4 C 4.66 4 5.2 4.54 5.2 5.2 L 5.2 20.2 C 5.2 20.86 4.66 21.4 4 21.4 L 3.8 21.4 C 3.14 21.4 2.6 20.86 2.6 20.2 L 2.6 5.2 C 2.6 4.54 3.14 4 3.8 4 Z", 0),
            ("solid", "M 3.4 16.6 L 20.6 16.6 C 21.04 16.6 21.4 16.96 21.4 17.4 L 21.4 18.4 C 21.4 18.84 21.04 19.2 20.6 19.2 L 3.4 19.2 C 2.96 19.2 2.6 18.84 2.6 18.4 L 2.6 17.4 C 2.6 16.96 2.96 16.6 3.4 16.6 Z", 0),
            ("solid", "M 20 16.6 L 20.2 16.6 C 20.86 16.6 21.4 17.14 21.4 17.8 L 21.4 20.2 C 21.4 20.86 20.86 21.4 20.2 21.4 L 20 21.4 C 19.34 21.4 18.8 20.86 18.8 20.2 L 18.8 17.8 C 18.8 17.14 19.34 16.6 20 16.6 Z", 0),
            ("solid", "M 8 7.6 L 10.2 7.6 C 11.08 7.6 11.8 8.32 11.8 9.2 L 11.8 9.6 C 11.8 10.48 11.08 11.2 10.2 11.2 L 8 11.2 C 7.12 11.2 6.4 10.48 6.4 9.6 L 6.4 9.2 C 6.4 8.32 7.12 7.6 8 7.6 Z", 0),
            ("hi", "M 15.6 15.32 C 15.04 14.84 14 14.12 14 13.32 C 14 12.44 15.12 12.12 15.6 13 C 16.08 12.12 17.2 12.44 17.2 13.32 C 17.2 14.12 16.16 14.84 15.6 15.32 Z", 0),
        ]
        case .visa: [
            ("soft", "M 7 2.4 L 17 2.4 C 18.44 2.4 19.6 3.56 19.6 5 L 19.6 19 C 19.6 20.44 18.44 21.6 17 21.6 L 7 21.6 C 5.56 21.6 4.4 20.44 4.4 19 L 4.4 5 C 4.4 3.56 5.56 2.4 7 2.4 Z", 0),
            ("solid", "M 6 2.4 L 7.6 2.4 L 7.6 21.6 L 6 21.6 C 5.12 21.6 4.4 20.88 4.4 20 L 4.4 4 C 4.4 3.12 5.12 2.4 6 2.4 Z", 0),
            ("solid", "M 17.2 10 C 17.2 11.99 15.59 13.6 13.6 13.6 C 11.61 13.6 10 11.99 10 10 C 10 8.01 11.61 6.4 13.6 6.4 C 15.59 6.4 17.2 8.01 17.2 10 Z", 0),
            ("hi", "M 15 10 C 15 10.77 14.37 11.4 13.6 11.4 C 12.83 11.4 12.2 10.77 12.2 10 C 12.2 9.23 12.83 8.6 13.6 8.6 C 14.37 8.6 15 9.23 15 10 Z", 0),
            ("solid", "M 10.6 17 L 16.6 17", 1.5),
        ]
        case .redpacket: [
            ("soft", "M 7.4 2.4 L 16.6 2.4 C 18.26 2.4 19.6 3.74 19.6 5.4 L 19.6 18.6 C 19.6 20.26 18.26 21.6 16.6 21.6 L 7.4 21.6 C 5.74 21.6 4.4 20.26 4.4 18.6 L 4.4 5.4 C 4.4 3.74 5.74 2.4 7.4 2.4 Z", 0),
            ("solid", "M 4.4 5.4 C 4.4 3.6 5.6 2.4 7.4 2.4 L 16.6 2.4 C 18.4 2.4 19.6 3.6 19.6 5.4 L 19.6 9 C 17.4 10.6 14.8 11.4 12 11.4 C 9.2 11.4 6.6 10.6 4.4 9 Z", 0),
            ("solid:F5B300", "M 14.8 11.4 C 14.8 12.95 13.55 14.2 12 14.2 C 10.45 14.2 9.2 12.95 9.2 11.4 C 9.2 9.85 10.45 8.6 12 8.6 C 13.55 8.6 14.8 9.85 14.8 11.4 Z", 0),
            ("hi", "M 12 10.3 C 12.21 11.19 12.21 11.19 13.1 11.4 C 12.21 11.61 12.21 11.61 12 12.5 C 11.79 11.61 11.79 11.61 10.9 11.4 C 11.79 11.19 11.79 11.19 12 10.3 Z", 0),
        ]
        case .family: [
            ("soft", "M 2.4 20.4 C 2.4 16.4 4.8 14 8 14 C 11.2 14 13.6 16.4 13.6 20.4 Z", 0),
            ("solid", "M 11.6 9 C 11.6 10.99 9.99 12.6 8 12.6 C 6.01 12.6 4.4 10.99 4.4 9 C 4.4 7.01 6.01 5.4 8 5.4 C 9.99 5.4 11.6 7.01 11.6 9 Z", 0),
            ("soft", "M 12.6 20.4 C 12.8 17.2 14.6 15.4 17 15.4 C 19.6 15.4 21.6 17.4 21.6 20.4 Z", 0),
            ("solid", "M 19.8 11.2 C 19.8 12.75 18.55 14 17 14 C 15.45 14 14.2 12.75 14.2 11.2 C 14.2 9.65 15.45 8.4 17 8.4 C 18.55 8.4 19.8 9.65 19.8 11.2 Z", 0),
            ("solid", "M 13 5.9 C 12.3 5.3 11 4.4 11 3.4 C 11 2.3 12.4 1.9 13 3 C 13.6 1.9 15 2.3 15 3.4 C 15 4.4 13.7 5.3 13 5.9 Z", 0),
        ]
        case .donation: [
            ("soft", "M 2.4 14 L 6 14 L 10.4 15.4 C 11.4 15.8 11.6 17 10.8 17.4 L 8.4 17.6 L 13.6 18.6 L 19.2 15.6 C 20.2 15 21.4 15.8 21 16.8 C 20.8 17.4 20.4 17.8 19.8 18.2 L 14.4 21.4 L 2.4 21.4 Z", 0),
            ("solid", "M 13.6 12.96 C 11.92 11.52 8.8 9.36 8.8 6.96 C 8.8 4.32 12.16 3.36 13.6 6 C 15.04 3.36 18.4 4.32 18.4 6.96 C 18.4 9.36 15.28 11.52 13.6 12.96 Z", 0),
            ("hi", "M 10.6 7.4 C 10.8 6.4 11.6 5.8 12.4 5.8", 1.2),
        ]
        case .wedding: [
            ("soft", "M 15 14.4 C 15 17.71 12.31 20.4 9 20.4 C 5.69 20.4 3 17.71 3 14.4 C 3 11.09 5.69 8.4 9 8.4 C 12.31 8.4 15 11.09 15 14.4 Z", 0),
            ("solid", "M 15 14.4 C 15 17.71 12.31 20.4 9 20.4 C 5.69 20.4 3 17.71 3 14.4 C 3 11.09 5.69 8.4 9 8.4 C 12.31 8.4 15 11.09 15 14.4 Z", 1.8),
            ("solid", "M 21 14.4 C 21 17.71 18.31 20.4 15 20.4 C 11.69 20.4 9 17.71 9 14.4 C 9 11.09 11.69 8.4 15 8.4 C 18.31 8.4 21 11.09 21 14.4 Z", 0),
            ("cut", "M 19.2 14.4 C 19.2 16.72 17.32 18.6 15 18.6 C 12.68 18.6 10.8 16.72 10.8 14.4 C 10.8 12.08 12.68 10.2 15 10.2 C 17.32 10.2 19.2 12.08 19.2 14.4 Z", 0),
            ("solid", "M 12.54 3.66 C 12.83 3.25 13.3 3 13.8 3 L 16.2 3 C 16.7 3 17.17 3.25 17.46 3.66 L 17.94 4.34 C 18.23 4.75 18.17 5.2 17.8 5.53 L 15.6 7.47 C 15.23 7.8 14.77 7.8 14.4 7.47 L 12.2 5.53 C 11.83 5.2 11.77 4.75 12.06 4.34 Z", 0),
        ]
        case .elderly: [
            ("soft", "M 6.4 8.6 L 17.6 8.6 C 19.48 8.6 21 10.12 21 12 L 21 18 C 21 19.88 19.48 21.4 17.6 21.4 L 6.4 21.4 C 4.52 21.4 3 19.88 3 18 L 3 12 C 3 10.12 4.52 8.6 6.4 8.6 Z", 0),
            ("solid", "M 12 21.4 C 12 21.4 5 17.4 5 13 C 5 11 6.4 9.8 8.2 9.8 C 9.8 9.8 11 10.8 12 12.2 C 13 10.8 14.2 9.8 15.8 9.8 C 17.6 9.8 19 11 19 13 C 19 17.4 12 21.4 12 21.4 Z", 0),
            ("solid", "M 9.4 4 L 14.6 4 C 15.7 4 16.6 4.9 16.6 6 L 16.6 7.2 C 16.6 8.3 15.7 9.2 14.6 9.2 L 9.4 9.2 C 8.3 9.2 7.4 8.3 7.4 7.2 L 7.4 6 C 7.4 4.9 8.3 4 9.4 4 Z", 0),
            ("hi", "M 7.4 13 L 8.6 12", 1.1),
        ]
        case .school: [
            ("solid", "M 8.4 6 C 8.4 3.8 10 2.4 12 2.4 C 14 2.4 15.6 3.8 15.6 6", 1.8),
            ("soft", "M 8.4 5.6 L 15.6 5.6 C 18.03 5.6 20 7.57 20 10 L 20 17.2 C 20 19.63 18.03 21.6 15.6 21.6 L 8.4 21.6 C 5.97 21.6 4 19.63 4 17.2 L 4 10 C 4 7.57 5.97 5.6 8.4 5.6 Z", 0),
            ("solid", "M 4 9.6 C 4 7.4 5.8 5.6 8 5.6 L 16 5.6 C 18.2 5.6 20 7.4 20 9.6 L 20 12 L 4 12 Z", 0),
            ("solid", "M 10 14.4 L 14 14.4 C 14.88 14.4 15.6 15.12 15.6 16 L 15.6 17.4 C 15.6 18.28 14.88 19 14 19 L 10 19 C 9.12 19 8.4 18.28 8.4 17.4 L 8.4 16 C 8.4 15.12 9.12 14.4 10 14.4 Z", 0),
            ("hi", "M 12.9 16.6 C 12.9 17.1 12.5 17.5 12 17.5 C 11.5 17.5 11.1 17.1 11.1 16.6 C 11.1 16.1 11.5 15.7 12 15.7 C 12.5 15.7 12.9 16.1 12.9 16.6 Z", 0),
        ]
        case .babycare: [
            ("soft", "M 3 9 L 21 9 C 21 14.6 17 18.4 12 18.4 C 7 18.4 3 14.6 3 9 Z", 0),
            ("solid", "M 12 9 L 12 2.8 C 16.8 2.8 21 5.6 21 9 Z", 0),
            ("solid", "M 3 9 L 1.6 6.6", 1.6),
            ("solid", "M 9.2 20.6 C 9.2 21.59 8.39 22.4 7.4 22.4 C 6.41 22.4 5.6 21.59 5.6 20.6 C 5.6 19.61 6.41 18.8 7.4 18.8 C 8.39 18.8 9.2 19.61 9.2 20.6 Z", 0),
            ("solid", "M 18.4 20.6 C 18.4 21.59 17.59 22.4 16.6 22.4 C 15.61 22.4 14.8 21.59 14.8 20.6 C 14.8 19.61 15.61 18.8 16.6 18.8 C 17.59 18.8 18.4 19.61 18.4 20.6 Z", 0),
            ("hi", "M 8 14.12 C 7.44 13.64 6.4 12.92 6.4 12.12 C 6.4 11.24 7.52 10.92 8 11.8 C 8.48 10.92 9.6 11.24 9.6 12.12 C 9.6 12.92 8.56 13.64 8 14.12 Z", 0),
        ]
        case .course: [
            ("solid", "M 19.2 9.6 L 19.2 15", 1.6),
            ("solid", "M 20.6 15.8 C 20.6 16.57 19.97 17.2 19.2 17.2 C 18.43 17.2 17.8 16.57 17.8 15.8 C 17.8 15.03 18.43 14.4 19.2 14.4 C 19.97 14.4 20.6 15.03 20.6 15.8 Z", 0),
            ("soft", "M 6.4 11.6 L 6.4 16.4 C 6.4 18 9 19.4 12 19.4 C 15 19.4 17.6 18 17.6 16.4 L 17.6 11.6 Z", 0),
            ("solid", "M 10.91 4.5 C 11.59 4.19 12.41 4.19 13.09 4.5 L 21.31 8.3 C 21.99 8.61 21.99 8.99 21.31 9.3 L 13.09 13.1 C 12.41 13.41 11.59 13.41 10.91 13.1 L 2.69 9.3 C 2.01 8.99 2.01 8.61 2.69 8.3 Z", 0),
            ("hi", "M 13 8.8 C 13 9.35 12.55 9.8 12 9.8 C 11.45 9.8 11 9.35 11 8.8 C 11 8.25 11.45 7.8 12 7.8 C 12.55 7.8 13 8.25 13 8.8 Z", 0),
        ]
        case .office: [
            ("solid", "M 10.2 3.2 L 13.8 3.2 C 14.79 3.2 15.6 4.01 15.6 5 L 15.6 6.4 C 15.6 7.39 14.79 8.2 13.8 8.2 L 10.2 8.2 C 9.21 8.2 8.4 7.39 8.4 6.4 L 8.4 5 C 8.4 4.01 9.21 3.2 10.2 3.2 Z", 1.7),
            ("soft", "M 5.6 7 L 18.4 7 C 20.06 7 21.4 8.34 21.4 10 L 21.4 17.6 C 21.4 19.26 20.06 20.6 18.4 20.6 L 5.6 20.6 C 3.94 20.6 2.6 19.26 2.6 17.6 L 2.6 10 C 2.6 8.34 3.94 7 5.6 7 Z", 0),
            ("solid", "M 2.6 10 C 2.6 8.4 3.8 7 5.6 7 L 18.4 7 C 20.2 7 21.4 8.4 21.4 10 L 21.4 12.6 C 18.6 14 15.4 14.6 12 14.6 C 8.6 14.6 5.4 14 2.6 12.6 Z", 0),
            ("hi", "M 11.6 12.6 L 12.4 12.6 C 12.95 12.6 13.4 13.05 13.4 13.6 L 13.4 14.8 C 13.4 15.35 12.95 15.8 12.4 15.8 L 11.6 15.8 C 11.05 15.8 10.6 15.35 10.6 14.8 L 10.6 13.6 C 10.6 13.05 11.05 12.6 11.6 12.6 Z", 0),
        ]
        case .software: [
            ("soft", "M 6 3.6 L 18 3.6 C 19.88 3.6 21.4 5.12 21.4 7 L 21.4 17 C 21.4 18.88 19.88 20.4 18 20.4 L 6 20.4 C 4.12 20.4 2.6 18.88 2.6 17 L 2.6 7 C 2.6 5.12 4.12 3.6 6 3.6 Z", 0),
            ("solid", "M 4.8 3.6 L 19.2 3.6 C 20.42 3.6 21.4 4.58 21.4 5.8 L 21.4 8 L 2.6 8 L 2.6 5.8 C 2.6 4.58 3.58 3.6 4.8 3.6 Z", 0),
            ("hi", "M 6.4 5.8 C 6.4 6.24 6.04 6.6 5.6 6.6 C 5.16 6.6 4.8 6.24 4.8 5.8 C 4.8 5.36 5.16 5 5.6 5 C 6.04 5 6.4 5.36 6.4 5.8 Z", 0),
            ("hi", "M 8.8 5.8 C 8.8 6.24 8.44 6.6 8 6.6 C 7.56 6.6 7.2 6.24 7.2 5.8 C 7.2 5.36 7.56 5 8 5 C 8.44 5 8.8 5.36 8.8 5.8 Z", 0),
            ("solid", "M 9.6 11.4 L 7 14 L 9.6 16.6", 1.8),
            ("solid", "M 14.4 11.4 L 17 14 L 14.4 16.6", 1.8),
        ]
        case .website: [
            ("soft", "M 21.4 12 C 21.4 17.19 17.19 21.4 12 21.4 C 6.81 21.4 2.6 17.19 2.6 12 C 2.6 6.81 6.81 2.6 12 2.6 C 17.19 2.6 21.4 6.81 21.4 12 Z", 0),
            ("solid", "M 16 12 C 16 17.19 14.21 21.4 12 21.4 C 9.79 21.4 8 17.19 8 12 C 8 6.81 9.79 2.6 12 2.6 C 14.21 2.6 16 6.81 16 12 Z", 1.6),
            ("solid", "M 2.8 12 L 21.2 12", 1.6),
            ("solid", "M 4.4 7 C 9 8.4 15 8.4 19.6 7", 1.4),
            ("solid", "M 4.4 17 C 9 15.6 15 15.6 19.6 17", 1.4),
        ]
        case .sidejob: [
            ("soft", "M 5.2 4 L 15.8 4 C 17.02 4 18 4.98 18 6.2 L 18 12.4 C 18 13.62 17.02 14.6 15.8 14.6 L 5.2 14.6 C 3.98 14.6 3 13.62 3 12.4 L 3 6.2 C 3 4.98 3.98 4 5.2 4 Z", 0),
            ("solid", "M 1.4 15.6 L 19.6 15.6 L 19.6 16.4 C 19.6 17.6 18.6 18.6 17.4 18.6 L 3.6 18.6 C 2.4 18.6 1.4 17.6 1.4 16.4 Z", 0),
            ("solid", "M 23 15.2 C 23 17.63 21.03 19.6 18.6 19.6 C 16.17 19.6 14.2 17.63 14.2 15.2 C 14.2 12.77 16.17 10.8 18.6 10.8 C 21.03 10.8 23 12.77 23 15.2 Z", 0),
            ("hi", "M 18.6 13.5 C 18.92 14.88 18.92 14.88 20.3 15.2 C 18.92 15.52 18.92 15.52 18.6 16.9 C 18.28 15.52 18.28 15.52 16.9 15.2 C 18.28 14.88 18.28 14.88 18.6 13.5 Z", 0),
            ("hi", "M 5.6 7 L 8 7", 1.2),
        ]
        case .bonus: [
            ("solid", "M 7 6 L 3.6 6 C 3.6 9.4 5 11 7.4 11", 1.7),
            ("solid", "M 17 6 L 20.4 6 C 20.4 9.4 19 11 16.6 11", 1.7),
            ("soft", "M 9.4 17 L 14.6 17 C 15.15 17 15.6 17.45 15.6 18 L 15.6 18.6 C 15.6 19.15 15.15 19.6 14.6 19.6 L 9.4 19.6 C 8.85 19.6 8.4 19.15 8.4 18.6 L 8.4 18 C 8.4 17.45 8.85 17 9.4 17 Z", 0),
            ("solid", "M 7.2 19 L 16.8 19 C 17.46 19 18 19.54 18 20.2 L 18 20.4 C 18 21.06 17.46 21.6 16.8 21.6 L 7.2 21.6 C 6.54 21.6 6 21.06 6 20.4 L 6 20.2 C 6 19.54 6.54 19 7.2 19 Z", 0),
            ("solid", "M 6.6 3 L 17.4 3 L 17.4 8.6 C 17.4 11.8 15 14.4 12 14.4 C 9 14.4 6.6 11.8 6.6 8.6 Z", 0),
            ("solid", "M 12 14 L 12 17.4", 2),
            ("hi", "M 11.82 5.96 C 11.93 5.74 12.07 5.74 12.18 5.96 L 12.59 6.79 C 12.7 7.01 12.91 7.17 13.16 7.21 L 14.08 7.34 C 14.32 7.37 14.36 7.5 14.19 7.68 L 13.52 8.32 C 13.35 8.5 13.26 8.75 13.3 9 L 13.46 9.91 C 13.5 10.15 13.39 10.23 13.17 10.12 L 12.35 9.69 C 12.13 9.57 11.87 9.57 11.65 9.69 L 10.83 10.12 C 10.61 10.23 10.5 10.15 10.54 9.91 L 10.7 9 C 10.74 8.75 10.65 8.5 10.48 8.32 L 9.81 7.68 C 9.64 7.5 9.68 7.37 9.92 7.34 L 10.84 7.21 C 11.09 7.17 11.3 7.01 11.41 6.79 Z", 0),
        ]
        case .reimburse: [
            ("soft", "M 5 2.6 L 19 2.6 L 19 21 L 16.7 19.6 L 14.4 21 L 12 19.6 L 9.6 21 L 7.3 19.6 L 5 21 Z", 0),
            ("solid", "M 8 6.6 L 16 6.6", 1.5),
            ("solid", "M 8 10 L 12.6 10", 1.5),
            ("solid", "M 19 15 C 19 16.99 17.39 18.6 15.4 18.6 C 13.41 18.6 11.8 16.99 11.8 15 C 11.8 13.01 13.41 11.4 15.4 11.4 C 17.39 11.4 19 13.01 19 15 Z", 0),
            ("hi", "M 13.8 15.1 L 15 16.3 L 17 14", 1.3),
        ]
        case .rentincome: [
            ("soft", "M 12.8 9.4 C 12.8 12.27 10.47 14.6 7.6 14.6 C 4.73 14.6 2.4 12.27 2.4 9.4 C 2.4 6.53 4.73 4.2 7.6 4.2 C 10.47 4.2 12.8 6.53 12.8 9.4 Z", 0),
            ("cut", "M 8.4 8.6 C 8.4 9.48 7.68 10.2 6.8 10.2 C 5.92 10.2 5.2 9.48 5.2 8.6 C 5.2 7.72 5.92 7 6.8 7 C 7.68 7 8.4 7.72 8.4 8.6 Z", 0),
            ("solid", "M 10.8 12 L 20.4 21.6 L 17 21.6 L 17 19.6 L 15 19.6 L 15 17.6 L 13 17.6 L 9.6 14.2 Z", 0),
            ("solid", "M 12.8 9.4 C 12.8 12.27 10.47 14.6 7.6 14.6 C 4.73 14.6 2.4 12.27 2.4 9.4 C 2.4 6.53 4.73 4.2 7.6 4.2 C 10.47 4.2 12.8 6.53 12.8 9.4 Z", 1.6),
            ("hi", "M 6.3 7.2 C 6.3 7.59 5.99 7.9 5.6 7.9 C 5.21 7.9 4.9 7.59 4.9 7.2 C 4.9 6.81 5.21 6.5 5.6 6.5 C 5.99 6.5 6.3 6.81 6.3 7.2 Z", 0),
        ]
        case .resale: [
            ("soft", "M 3 12.4 L 3 4.6 C 3 3.7 3.7 3 4.6 3 L 12.4 3 L 21 11.6 C 21.6 12.2 21.6 13.2 21 13.8 L 13.8 21 C 13.2 21.6 12.2 21.6 11.6 21 Z", 0),
            ("solid", "M 9.2 7.4 C 9.2 8.39 8.39 9.2 7.4 9.2 C 6.41 9.2 5.6 8.39 5.6 7.4 C 5.6 6.41 6.41 5.6 7.4 5.6 C 8.39 5.6 9.2 6.41 9.2 7.4 Z", 0),
            ("solid", "M 10.21 12.24 C 10.66 11 11.79 10.13 13.1 10.01 C 14.42 9.9 15.68 10.56 16.34 11.7", 1.6),
            ("solid", "M 16.36 9.92 C 16.51 9.72 16.65 9.74 16.73 9.98 L 17.47 12.02 C 17.55 12.26 17.45 12.39 17.2 12.37 L 15 12.23 C 14.75 12.21 14.69 12.08 14.84 11.88 Z", 0),
            ("solid", "M 16.59 14.56 C 16.14 15.8 15.01 16.67 13.7 16.79 C 12.38 16.9 11.12 16.24 10.46 15.1", 1.6),
            ("solid", "M 10.44 16.88 C 10.29 17.08 10.15 17.06 10.07 16.82 L 9.33 14.78 C 9.25 14.54 9.35 14.41 9.6 14.43 L 11.8 14.57 C 12.05 14.59 12.11 14.72 11.96 14.92 Z", 0),
        ]
        case .interest: [
            ("soft", "M 18.4 13 C 18.4 17.64 14.64 21.4 10 21.4 C 5.36 21.4 1.6 17.64 1.6 13 C 1.6 8.36 5.36 4.6 10 4.6 C 14.64 4.6 18.4 8.36 18.4 13 Z", 0),
            ("solid", "M 14.6 13 C 14.6 15.54 12.54 17.6 10 17.6 C 7.46 17.6 5.4 15.54 5.4 13 C 5.4 10.46 7.46 8.4 10 8.4 C 12.54 8.4 14.6 10.46 14.6 13 Z", 0),
            ("hi", "M 10 11.2 C 10.34 12.66 10.34 12.66 11.8 13 C 10.34 13.34 10.34 13.34 10 14.8 C 9.66 13.34 9.66 13.34 8.2 13 C 9.66 12.66 9.66 12.66 10 11.2 Z", 0),
            ("solid", "M 15.4 7.4 L 21 2.4", 2),
            ("solid", "M 17.42 2.22 C 17.16 1.96 17.23 1.77 17.6 1.73 L 21.6 1.27 C 21.97 1.23 22.17 1.43 22.13 1.8 L 21.67 5.8 C 21.63 6.17 21.44 6.24 21.18 5.98 Z", 0),
        ]
        case .taxrefund: [
            ("soft", "M 5 2.6 L 19 2.6 L 19 21 L 16.7 19.6 L 14.4 21 L 12 19.6 L 9.6 21 L 7.3 19.6 L 5 21 Z", 0),
            ("solid", "M 8 6.6 L 16 6.6", 1.5),
            ("solid", "M 15.8 13.2 C 15.8 15.3 14.1 17 12 17 C 9.9 17 8.2 15.3 8.2 13.2 C 8.2 11.1 9.9 9.4 12 9.4 C 14.1 9.4 15.8 11.1 15.8 13.2 Z", 0),
            ("hi", "M 13.6 11.6 C 12.4 10.8 10.4 11.4 10.4 13.2 C 10.4 15 12.4 15.6 13.6 14.8", 1.1),
        ]
        case .cardpay: [
            ("soft", "M 4.8 4.6 L 16.2 4.6 C 17.75 4.6 19 5.85 19 7.4 L 19 13.8 C 19 15.35 17.75 16.6 16.2 16.6 L 4.8 16.6 C 3.25 16.6 2 15.35 2 13.8 L 2 7.4 C 2 5.85 3.25 4.6 4.8 4.6 Z", 0),
            ("solid", "M 2 7.6 L 19 7.6 L 19 10.2 L 2 10.2 L 2 7.6 Z", 0),
            ("solid", "M 22.6 16.4 C 22.6 18.94 20.54 21 18 21 C 15.46 21 13.4 18.94 13.4 16.4 C 13.4 13.86 15.46 11.8 18 11.8 C 20.54 11.8 22.6 13.86 22.6 16.4 Z", 0),
            ("hi", "M 15.8 16.6 L 17.4 18.2 L 20.2 15", 1.6),
        ]
        case .installment: [
            ("soft", "M 6.4 4.6 L 17.6 4.6 C 19.48 4.6 21 6.12 21 8 L 21 17.8 C 21 19.68 19.48 21.2 17.6 21.2 L 6.4 21.2 C 4.52 21.2 3 19.68 3 17.8 L 3 8 C 3 6.12 4.52 4.6 6.4 4.6 Z", 0),
            ("solid", "M 5.5 4.6 L 18.5 4.6 C 19.88 4.6 21 5.72 21 7.1 L 21 9.6 L 3 9.6 L 3 7.1 C 3 5.72 4.12 4.6 5.5 4.6 Z", 0),
            ("solid", "M 8.1 2.4 L 8.1 2.4 C 8.71 2.4 9.2 2.89 9.2 3.5 L 9.2 5.7 C 9.2 6.31 8.71 6.8 8.1 6.8 L 8.1 6.8 C 7.49 6.8 7 6.31 7 5.7 L 7 3.5 C 7 2.89 7.49 2.4 8.1 2.4 Z", 0),
            ("solid", "M 15.9 2.4 L 15.9 2.4 C 16.51 2.4 17 2.89 17 3.5 L 17 5.7 C 17 6.31 16.51 6.8 15.9 6.8 L 15.9 6.8 C 15.29 6.8 14.8 6.31 14.8 5.7 L 14.8 3.5 C 14.8 2.89 15.29 2.4 15.9 2.4 Z", 0),
            ("solid", "M 9.8 14.6 C 9.8 15.48 9.08 16.2 8.2 16.2 C 7.32 16.2 6.6 15.48 6.6 14.6 C 6.6 13.72 7.32 13 8.2 13 C 9.08 13 9.8 13.72 9.8 14.6 Z", 0),
            ("solid", "M 13.6 14.6 C 13.6 15.48 12.88 16.2 12 16.2 C 11.12 16.2 10.4 15.48 10.4 14.6 C 10.4 13.72 11.12 13 12 13 C 12.88 13 13.6 13.72 13.6 14.6 Z", 0),
            ("soft", "M 17.4 14.6 C 17.4 15.48 16.68 16.2 15.8 16.2 C 14.92 16.2 14.2 15.48 14.2 14.6 C 14.2 13.72 14.92 13 15.8 13 C 16.68 13 17.4 13.72 17.4 14.6 Z", 0),
            ("solid", "M 17.4 14.6 C 17.4 15.48 16.68 16.2 15.8 16.2 C 14.92 16.2 14.2 15.48 14.2 14.6 C 14.2 13.72 14.92 13 15.8 13 C 16.68 13 17.4 13.72 17.4 14.6 Z", 1),
        ]
        case .exchange: [
            ("soft", "M 14.2 8.4 C 14.2 11.6 11.6 14.2 8.4 14.2 C 5.2 14.2 2.6 11.6 2.6 8.4 C 2.6 5.2 5.2 2.6 8.4 2.6 C 11.6 2.6 14.2 5.2 14.2 8.4 Z", 0),
            ("solid", "M 21.4 15.6 C 21.4 18.8 18.8 21.4 15.6 21.4 C 12.4 21.4 9.8 18.8 9.8 15.6 C 9.8 12.4 12.4 9.8 15.6 9.8 C 18.8 9.8 21.4 12.4 21.4 15.6 Z", 0),
            ("hi", "M 17.4 13.6 C 16.2 12.8 13.8 13.4 13.8 15.6 C 13.8 17.8 16.2 18.4 17.4 17.6", 1.2),
            ("solid", "M 6.8 6.4 C 7.6 5.8 9.6 6 9.6 7.6 C 9.6 8.8 7.2 9 7.2 10.6 L 10 10.6", 1.3),
            ("solid", "M 17.4 3.4 C 19.4 4 20.6 5.6 20.6 7.6", 1.5),
            ("solid", "M 19.04 7.52 C 18.89 7.32 18.95 7.2 19.2 7.2 L 22 7.2 C 22.25 7.2 22.31 7.32 22.16 7.52 L 20.84 9.28 C 20.69 9.48 20.51 9.48 20.36 9.28 Z", 0),
        ]
        case .stocks: [
            ("soft", "M 6 3 L 18 3 C 19.88 3 21.4 4.52 21.4 6.4 L 21.4 17.6 C 21.4 19.48 19.88 21 18 21 L 6 21 C 4.12 21 2.6 19.48 2.6 17.6 L 2.6 6.4 C 2.6 4.52 4.12 3 6 3 Z", 0),
            ("solid", "M 5.6 16.4 L 9.6 11.6 L 12.6 14 L 18.4 7.4", 2),
            ("solid", "M 15.02 6.82 C 14.76 6.56 14.83 6.39 15.2 6.38 L 18.8 6.22 C 19.17 6.21 19.39 6.43 19.38 6.8 L 19.22 10.4 C 19.21 10.77 19.04 10.84 18.78 10.58 Z", 0),
        ]
        case .fine: [
            ("soft", "M 7 2.6 L 17 2.6 C 18.66 2.6 20 3.94 20 5.6 L 20 18.4 C 20 20.06 18.66 21.4 17 21.4 L 7 21.4 C 5.34 21.4 4 20.06 4 18.4 L 4 5.6 C 4 3.94 5.34 2.6 7 2.6 Z", 0),
            ("solid", "M 6.3 2.6 L 17.7 2.6 C 18.97 2.6 20 3.63 20 4.9 L 20 7.2 L 4 7.2 L 4 4.9 C 4 3.63 5.03 2.6 6.3 2.6 Z", 0),
            ("solid", "M 12 10.4 L 12 14.6", 2.2),
            ("solid", "M 13.3 17.6 C 13.3 18.32 12.72 18.9 12 18.9 C 11.28 18.9 10.7 18.32 10.7 17.6 C 10.7 16.88 11.28 16.3 12 16.3 C 12.72 16.3 13.3 16.88 13.3 17.6 Z", 0),
        ]
        case .bankfee: [
            ("soft", "M 5.2 10.6 L 6.4 10.6 C 6.73 10.6 7 10.87 7 11.2 L 7 16.8 C 7 17.13 6.73 17.4 6.4 17.4 L 5.2 17.4 C 4.87 17.4 4.6 17.13 4.6 16.8 L 4.6 11.2 C 4.6 10.87 4.87 10.6 5.2 10.6 Z", 0),
            ("soft", "M 11.4 10.6 L 12.6 10.6 C 12.93 10.6 13.2 10.87 13.2 11.2 L 13.2 16.8 C 13.2 17.13 12.93 17.4 12.6 17.4 L 11.4 17.4 C 11.07 17.4 10.8 17.13 10.8 16.8 L 10.8 11.2 C 10.8 10.87 11.07 10.6 11.4 10.6 Z", 0),
            ("solid", "M 10.76 2.99 C 11.4 2.63 12.2 2.63 12.84 2.99 L 19.67 6.87 C 20.25 7.2 20.6 7.81 20.6 8.47 L 20.6 8.53 C 20.6 9.19 20.19 9.6 19.53 9.6 L 4.07 9.6 C 3.41 9.6 3 9.19 3 8.53 L 3 8.47 C 3 7.81 3.35 7.2 3.93 6.87 Z", 0),
            ("solid", "M 4.2 17.6 L 13.8 17.6 C 14.46 17.6 15 18.14 15 18.8 L 15 19.2 C 15 19.86 14.46 20.4 13.8 20.4 L 4.2 20.4 C 3.54 20.4 3 19.86 3 19.2 L 3 18.8 C 3 18.14 3.54 17.6 4.2 17.6 Z", 0),
            ("solid:F7A21B", "M 22.8 16.6 C 22.8 18.92 20.92 20.8 18.6 20.8 C 16.28 20.8 14.4 18.92 14.4 16.6 C 14.4 14.28 16.28 12.4 18.6 12.4 C 20.92 12.4 22.8 14.28 22.8 16.6 Z", 0),
            ("hi", "M 18.1 15.2 C 18.1 15.7 17.7 16.1 17.2 16.1 C 16.7 16.1 16.3 15.7 16.3 15.2 C 16.3 14.7 16.7 14.3 17.2 14.3 C 17.7 14.3 18.1 14.7 18.1 15.2 Z", 0),
            ("hi", "M 20.9 18 C 20.9 18.5 20.5 18.9 20 18.9 C 19.5 18.9 19.1 18.5 19.1 18 C 19.1 17.5 19.5 17.1 20 17.1 C 20.5 17.1 20.9 17.5 20.9 18 Z", 0),
            ("hi", "M 20.2 14.8 L 17 18.4", 1),
        ]
        case .remit: [
            ("soft", "M 2.4 11.4 L 20.6 3.4 C 21.4 3 22.2 3.8 21.8 4.6 L 14 21.6 C 13.6 22.4 12.4 22.2 12.2 21.4 L 10.8 13.4 Z", 0),
            ("solid", "M 10.8 13.4 L 21.4 3.8 L 14 21.6 C 13.6 22.4 12.4 22.2 12.2 21.4 Z", 0),
            ("hi", "M 5.6 11.2 L 9.4 9.6", 1.2),
        ]
        case .debt: [
            ("soft", "M 5.6 3.4 L 13.8 3.4 C 15.24 3.4 16.4 4.56 16.4 6 L 16.4 18 C 16.4 19.44 15.24 20.6 13.8 20.6 L 5.6 20.6 C 4.16 20.6 3 19.44 3 18 L 3 6 C 3 4.56 4.16 3.4 5.6 3.4 Z", 0),
            ("solid", "M 6.2 8 L 13.2 8", 1.5),
            ("solid", "M 6.2 11.4 L 11 11.4", 1.5),
            ("solid", "M 21.6 16 C 21.6 18.76 19.36 21 16.6 21 C 13.84 21 11.6 18.76 11.6 16 C 11.6 13.24 13.84 11 16.6 11 C 19.36 11 21.6 13.24 21.6 16 Z", 0),
            ("hi", "M 16.6 13.4 L 16.6 16.4", 1.6),
            ("hi", "M 17.5 18.6 C 17.5 19.1 17.1 19.5 16.6 19.5 C 16.1 19.5 15.7 19.1 15.7 18.6 C 15.7 18.1 16.1 17.7 16.6 17.7 C 17.1 17.7 17.5 18.1 17.5 18.6 Z", 0),
        ]
        case .crypto: [
            ("soft", "M 10.27 3.01 C 11.34 2.38 12.66 2.38 13.73 3.01 L 18.87 5.99 C 19.94 6.62 20.6 7.76 20.6 9 L 20.6 15 C 20.6 16.24 19.94 17.38 18.87 18.01 L 13.73 20.99 C 12.66 21.62 11.34 21.62 10.27 20.99 L 5.13 18.01 C 4.06 17.38 3.4 16.24 3.4 15 L 3.4 9 C 3.4 7.76 4.06 6.62 5.13 5.99 Z", 0),
            ("solid", "M 17.6 12 C 17.6 15.09 15.09 17.6 12 17.6 C 8.91 17.6 6.4 15.09 6.4 12 C 6.4 8.91 8.91 6.4 12 6.4 C 15.09 6.4 17.6 8.91 17.6 12 Z", 0),
            ("hi", "M 12 9.8 C 12.42 11.58 12.42 11.58 14.2 12 C 12.42 12.42 12.42 12.42 12 14.2 C 11.58 12.42 11.58 12.42 9.8 12 C 11.58 11.58 11.58 11.58 12 9.8 Z", 0),
        ]
        case .shipping: [
            ("solid", "M 9 18.4 C 9 19.73 7.93 20.8 6.6 20.8 C 5.27 20.8 4.2 19.73 4.2 18.4 C 4.2 17.07 5.27 16 6.6 16 C 7.93 16 9 17.07 9 18.4 Z", 0),
            ("solid", "M 19.8 18.4 C 19.8 19.73 18.73 20.8 17.4 20.8 C 16.07 20.8 15 19.73 15 18.4 C 15 17.07 16.07 16 17.4 16 C 18.73 16 19.8 17.07 19.8 18.4 Z", 0),
            ("soft", "M 15 7.6 L 18.4 7.6 L 21.4 11.8 L 21.4 16.6 C 21.4 17.4 20.8 18 20 18 L 15 18 Z", 0),
            ("solid", "M 4.2 4.4 L 13.4 4.4 C 14.5 4.4 15.4 5.3 15.4 6.4 L 15.4 16 C 15.4 17.1 14.5 18 13.4 18 L 4.2 18 C 3.1 18 2.2 17.1 2.2 16 L 2.2 6.4 C 2.2 5.3 3.1 4.4 4.2 4.4 Z", 0),
            ("hi", "M 17.2 9.4 L 18.6 9.4 C 18.93 9.4 19.2 9.67 19.2 10 L 19.2 11.4 C 19.2 11.73 18.93 12 18.6 12 L 17.2 12 C 16.87 12 16.6 11.73 16.6 11.4 L 16.6 10 C 16.6 9.67 16.87 9.4 17.2 9.4 Z", 0),
            ("hi", "M 8.8 12.31 C 8.17 11.77 7 10.96 7 10.06 C 7 9.07 8.26 8.71 8.8 9.7 C 9.34 8.71 10.6 9.07 10.6 10.06 C 10.6 10.96 9.43 11.77 8.8 12.31 Z", 0),
        ]
        case .platformfee: [
            ("solid", "M 8.4 8.6 L 8.4 7 C 8.4 4.6 10 3 12 3 C 14 3 15.6 4.6 15.6 7 L 15.6 8.6", 1.8),
            ("soft", "M 4.44 9.59 C 4.54 8.23 5.44 7.4 6.8 7.4 L 17.2 7.4 C 18.56 7.4 19.46 8.23 19.56 9.59 L 20.24 18.81 C 20.34 20.17 19.56 21 18.2 21 L 5.8 21 C 4.44 21 3.66 20.17 3.76 18.81 Z", 0),
            ("solid", "M 11 12.4 C 11 13.28 10.28 14 9.4 14 C 8.52 14 7.8 13.28 7.8 12.4 C 7.8 11.52 8.52 10.8 9.4 10.8 C 10.28 10.8 11 11.52 11 12.4 Z", 0),
            ("solid", "M 16.2 17.2 C 16.2 18.08 15.48 18.8 14.6 18.8 C 13.72 18.8 13 18.08 13 17.2 C 13 16.32 13.72 15.6 14.6 15.6 C 15.48 15.6 16.2 16.32 16.2 17.2 Z", 0),
            ("solid", "M 15 11.6 L 9 18", 1.6),
        ]
        case .pos: [
            ("soft", "M 8 2.4 L 16 2.4 C 17.88 2.4 19.4 3.92 19.4 5.8 L 19.4 18.2 C 19.4 20.08 17.88 21.6 16 21.6 L 8 21.6 C 6.12 21.6 4.6 20.08 4.6 18.2 L 4.6 5.8 C 4.6 3.92 6.12 2.4 8 2.4 Z", 0),
            ("solid", "M 8.4 4.6 L 15.6 4.6 C 16.37 4.6 17 5.23 17 6 L 17 8.8 C 17 9.57 16.37 10.2 15.6 10.2 L 8.4 10.2 C 7.63 10.2 7 9.57 7 8.8 L 7 6 C 7 5.23 7.63 4.6 8.4 4.6 Z", 0),
            ("solid", "M 9.7 13.6 C 9.7 14.21 9.21 14.7 8.6 14.7 C 7.99 14.7 7.5 14.21 7.5 13.6 C 7.5 12.99 7.99 12.5 8.6 12.5 C 9.21 12.5 9.7 12.99 9.7 13.6 Z", 0),
            ("solid", "M 13.1 13.6 C 13.1 14.21 12.61 14.7 12 14.7 C 11.39 14.7 10.9 14.21 10.9 13.6 C 10.9 12.99 11.39 12.5 12 12.5 C 12.61 12.5 13.1 12.99 13.1 13.6 Z", 0),
            ("solid", "M 16.5 13.6 C 16.5 14.21 16.01 14.7 15.4 14.7 C 14.79 14.7 14.3 14.21 14.3 13.6 C 14.3 12.99 14.79 12.5 15.4 12.5 C 16.01 12.5 16.5 12.99 16.5 13.6 Z", 0),
            ("solid", "M 9.7 17.2 C 9.7 17.81 9.21 18.3 8.6 18.3 C 7.99 18.3 7.5 17.81 7.5 17.2 C 7.5 16.59 7.99 16.1 8.6 16.1 C 9.21 16.1 9.7 16.59 9.7 17.2 Z", 0),
            ("solid", "M 13.1 17.2 C 13.1 17.81 12.61 18.3 12 18.3 C 11.39 18.3 10.9 17.81 10.9 17.2 C 10.9 16.59 11.39 16.1 12 16.1 C 12.61 16.1 13.1 16.59 13.1 17.2 Z", 0),
            ("solid", "M 16.5 17.2 C 16.5 17.81 16.01 18.3 15.4 18.3 C 14.79 18.3 14.3 17.81 14.3 17.2 C 14.3 16.59 14.79 16.1 15.4 16.1 C 16.01 16.1 16.5 16.59 16.5 17.2 Z", 0),
            ("hi", "M 9 6.6 L 11 6.6", 1.1),
        ]
        case .renovation: [
            ("soft", "M 5 3 L 15.8 3 C 17.24 3 18.4 4.16 18.4 5.6 L 18.4 7.4 C 18.4 8.84 17.24 10 15.8 10 L 5 10 C 3.56 10 2.4 8.84 2.4 7.4 L 2.4 5.6 C 2.4 4.16 3.56 3 5 3 Z", 0),
            ("solid", "M 5.8 4.6 L 15 4.6 C 15.77 4.6 16.4 5.23 16.4 6 L 16.4 7 C 16.4 7.77 15.77 8.4 15 8.4 L 5.8 8.4 C 5.03 8.4 4.4 7.77 4.4 7 L 4.4 6 C 4.4 5.23 5.03 4.6 5.8 4.6 Z", 0),
            ("solid", "M 18.4 6.4 L 20.4 6.4 C 21.2 6.4 21.6 7 21.6 7.6 L 21.6 11 C 21.6 11.8 21 12.4 20.2 12.4 L 12 12.4 L 12 15", 1.7),
            ("solid", "M 11.8 14.6 L 12.2 14.6 C 13.19 14.6 14 15.41 14 16.4 L 14 20.2 C 14 21.19 13.19 22 12.2 22 L 11.8 22 C 10.81 22 10 21.19 10 20.2 L 10 16.4 C 10 15.41 10.81 14.6 11.8 14.6 Z", 0),
        ]
        case .accounting: [
            ("soft", "M 7.4 2.4 L 16.6 2.4 C 18.48 2.4 20 3.92 20 5.8 L 20 18.2 C 20 20.08 18.48 21.6 16.6 21.6 L 7.4 21.6 C 5.52 21.6 4 20.08 4 18.2 L 4 5.8 C 4 3.92 5.52 2.4 7.4 2.4 Z", 0),
            ("solid", "M 7.8 4.8 L 16.2 4.8 C 16.97 4.8 17.6 5.43 17.6 6.2 L 17.6 8 C 17.6 8.77 16.97 9.4 16.2 9.4 L 7.8 9.4 C 7.03 9.4 6.4 8.77 6.4 8 L 6.4 6.2 C 6.4 5.43 7.03 4.8 7.8 4.8 Z", 0),
            ("solid", "M 9.8 13 C 9.8 13.66 9.26 14.2 8.6 14.2 C 7.94 14.2 7.4 13.66 7.4 13 C 7.4 12.34 7.94 11.8 8.6 11.8 C 9.26 11.8 9.8 12.34 9.8 13 Z", 0),
            ("solid", "M 13.2 13 C 13.2 13.66 12.66 14.2 12 14.2 C 11.34 14.2 10.8 13.66 10.8 13 C 10.8 12.34 11.34 11.8 12 11.8 C 12.66 11.8 13.2 12.34 13.2 13 Z", 0),
            ("solid", "M 16.6 13 C 16.6 13.66 16.06 14.2 15.4 14.2 C 14.74 14.2 14.2 13.66 14.2 13 C 14.2 12.34 14.74 11.8 15.4 11.8 C 16.06 11.8 16.6 12.34 16.6 13 Z", 0),
            ("solid", "M 9.8 17 C 9.8 17.66 9.26 18.2 8.6 18.2 C 7.94 18.2 7.4 17.66 7.4 17 C 7.4 16.34 7.94 15.8 8.6 15.8 C 9.26 15.8 9.8 16.34 9.8 17 Z", 0),
            ("solid", "M 13.2 17 C 13.2 17.66 12.66 18.2 12 18.2 C 11.34 18.2 10.8 17.66 10.8 17 C 10.8 16.34 11.34 15.8 12 15.8 C 12.66 15.8 13.2 16.34 13.2 17 Z", 0),
            ("solid:F7A21B", "M 16.6 17 C 16.6 17.66 16.06 18.2 15.4 18.2 C 14.74 18.2 14.2 17.66 14.2 17 C 14.2 16.34 14.74 15.8 15.4 15.8 C 16.06 15.8 16.6 16.34 16.6 17 Z", 0),
            ("hi", "M 8.6 7.1 L 11 7.1", 1.1),
        ]
        case .rentEquip: [
            ("soft", "M 5.2 7 L 13.6 7 C 15.04 7 16.2 8.16 16.2 9.6 L 16.2 16.8 C 16.2 18.24 15.04 19.4 13.6 19.4 L 5.2 19.4 C 3.76 19.4 2.6 18.24 2.6 16.8 L 2.6 9.6 C 2.6 8.16 3.76 7 5.2 7 Z", 0),
            ("solid", "M 6.4 9.4 L 12.4 9.4 C 13.17 9.4 13.8 10.03 13.8 10.8 L 13.8 13.2 C 13.8 13.97 13.17 14.6 12.4 14.6 L 6.4 14.6 C 5.63 14.6 5 13.97 5 13.2 L 5 10.8 C 5 10.03 5.63 9.4 6.4 9.4 Z", 0),
            ("solid", "M 7.4 17 L 11.4 17 C 11.95 17 12.4 17.45 12.4 18 L 12.4 18.4 C 12.4 18.95 11.95 19.4 11.4 19.4 L 7.4 19.4 C 6.85 19.4 6.4 18.95 6.4 18.4 L 6.4 18 C 6.4 17.45 6.85 17 7.4 17 Z", 0),
            ("solid", "M 21.2 8 C 21.2 9.88 19.68 11.4 17.8 11.4 C 15.92 11.4 14.4 9.88 14.4 8 C 14.4 6.12 15.92 4.6 17.8 4.6 C 19.68 4.6 21.2 6.12 21.2 8 Z", 1.6),
            ("solid", "M 17.6 11 L 18 11 C 18.66 11 19.2 11.54 19.2 12.2 L 19.2 19.4 C 19.2 20.06 18.66 20.6 18 20.6 L 17.6 20.6 C 16.94 20.6 16.4 20.06 16.4 19.4 L 16.4 12.2 C 16.4 11.54 16.94 11 17.6 11 Z", 0),
            ("solid", "M 19.4 15.4 L 20.8 15.4 C 21.24 15.4 21.6 15.76 21.6 16.2 L 21.6 16.6 C 21.6 17.04 21.24 17.4 20.8 17.4 L 19.4 17.4 C 18.96 17.4 18.6 17.04 18.6 16.6 L 18.6 16.2 C 18.6 15.76 18.96 15.4 19.4 15.4 Z", 0),
        ]
        case .uniform: [
            ("soft", "M 8.4 3 L 3 5.4 L 3 20 C 3 20.6 3.4 21 4 21 L 20 21 C 20.6 21 21 20.6 21 20 L 21 5.4 L 15.6 3 L 12 7.4 Z", 0),
            ("solid", "M 8.4 3 L 12 7.4 L 10 10.2 L 7.4 4.4 Z", 0),
            ("solid", "M 15.6 3 L 12 7.4 L 14 10.2 L 16.6 4.4 Z", 0),
            ("solid", "M 15.4 13 L 17.4 13 C 17.95 13 18.4 13.45 18.4 14 L 18.4 15.4 C 18.4 15.95 17.95 16.4 17.4 16.4 L 15.4 16.4 C 14.85 16.4 14.4 15.95 14.4 15.4 L 14.4 14 C 14.4 13.45 14.85 13 15.4 13 Z", 0),
            ("solid", "M 12.9 12.6 C 12.9 13.1 12.5 13.5 12 13.5 C 11.5 13.5 11.1 13.1 11.1 12.6 C 11.1 12.1 11.5 11.7 12 11.7 C 12.5 11.7 12.9 12.1 12.9 12.6 Z", 0),
            ("solid", "M 12.9 16 C 12.9 16.5 12.5 16.9 12 16.9 C 11.5 16.9 11.1 16.5 11.1 16 C 11.1 15.5 11.5 15.1 12 15.1 C 12.5 15.1 12.9 15.5 12.9 16 Z", 0),
        ]
        case .license: [
            ("soft", "M 5.2 3.4 L 18.8 3.4 C 20.24 3.4 21.4 4.56 21.4 6 L 21.4 14.8 C 21.4 16.24 20.24 17.4 18.8 17.4 L 5.2 17.4 C 3.76 17.4 2.6 16.24 2.6 14.8 L 2.6 6 C 2.6 4.56 3.76 3.4 5.2 3.4 Z", 0),
            ("solid", "M 5.6 7.4 L 12.6 7.4", 1.5),
            ("solid", "M 5.6 10.6 L 10.4 10.6", 1.5),
            ("solid", "M 15.95 11.66 C 16.23 11.25 16.57 11.25 16.85 11.66 L 17.5 12.6 C 17.78 13.01 18.24 13.35 18.72 13.49 L 19.82 13.81 C 20.29 13.95 20.4 14.28 20.1 14.67 L 19.4 15.58 C 19.1 15.97 18.92 16.52 18.93 17.02 L 18.96 18.16 C 18.98 18.66 18.7 18.86 18.23 18.69 L 17.15 18.31 C 16.69 18.14 16.11 18.14 15.65 18.31 L 14.57 18.69 C 14.1 18.86 13.82 18.66 13.84 18.16 L 13.87 17.02 C 13.88 16.52 13.7 15.97 13.4 15.58 L 12.7 14.67 C 12.4 14.28 12.51 13.95 12.98 13.81 L 14.08 13.49 C 14.56 13.35 15.02 13.01 15.3 12.6 Z", 0),
            ("solid", "M 14.5 18 C 14.19 18 13.97 18.19 13.93 18.49 L 13.47 21.51 C 13.43 21.81 13.57 21.92 13.85 21.79 L 15.95 20.81 C 16.23 20.68 16.57 20.68 16.85 20.81 L 18.95 21.79 C 19.23 21.92 19.37 21.81 19.33 21.51 L 18.87 18.49 C 18.83 18.19 18.61 18 18.3 18 Z", 0),
        ]
        case .customer: [
            ("soft", "M 3.4 21 C 3.4 16.6 7.2 14 12 14 C 16.8 14 20.6 16.6 20.6 21 Z", 0),
            ("solid", "M 16.8 8 C 16.8 10.65 14.65 12.8 12 12.8 C 9.35 12.8 7.2 10.65 7.2 8 C 7.2 5.35 9.35 3.2 12 3.2 C 14.65 3.2 16.8 5.35 16.8 8 Z", 0),
            ("hi", "M 9.1 7.22 C 9.36 6.28 10.05 5.52 10.97 5.18", 1.2),
            ("hi", "M 12 19.72 C 11.44 19.24 10.4 18.52 10.4 17.72 C 10.4 16.84 11.52 16.52 12 17.4 C 12.48 16.52 13.6 16.84 13.6 17.72 C 13.6 18.52 12.56 19.24 12 19.72 Z", 0),
        ]
        case .star: [
            ("soft", "M 10.99 3.93 C 11.62 2.86 12.38 2.86 13.01 3.93 L 14.36 6.24 C 14.98 7.32 16.1 8.13 17.32 8.4 L 19.94 8.96 C 21.15 9.23 21.38 9.95 20.56 10.88 L 18.77 12.88 C 17.95 13.8 17.52 15.12 17.64 16.36 L 17.91 19.02 C 18.04 20.26 17.42 20.71 16.28 20.21 L 13.83 19.13 C 12.7 18.63 11.3 18.63 10.17 19.13 L 7.72 20.21 C 6.58 20.71 5.96 20.26 6.09 19.02 L 6.36 16.36 C 6.48 15.12 6.05 13.8 5.23 12.88 L 3.44 10.88 C 2.62 9.95 2.85 9.23 4.06 8.96 L 6.68 8.4 C 7.9 8.13 9.02 7.32 9.64 6.24 Z", 0),
            ("solid", "M 11.65 7.92 C 11.87 7.47 12.13 7.47 12.35 7.92 L 13.23 9.7 C 13.45 10.14 13.89 10.46 14.38 10.53 L 16.34 10.82 C 16.83 10.89 16.92 11.14 16.56 11.49 L 15.14 12.88 C 14.79 13.22 14.62 13.73 14.7 14.22 L 15.04 16.18 C 15.12 16.67 14.9 16.83 14.47 16.6 L 12.71 15.67 C 12.27 15.44 11.73 15.44 11.29 15.67 L 9.53 16.6 C 9.1 16.83 8.88 16.67 8.96 16.18 L 9.3 14.22 C 9.38 13.73 9.21 13.22 8.86 12.88 L 7.44 11.49 C 7.08 11.14 7.17 10.89 7.66 10.82 L 9.62 10.53 C 10.11 10.46 10.55 10.14 10.77 9.7 Z", 0),
            ("hi", "M 7.2 10.2 C 7.2 9.53 7.62 8.93 8.25 8.7", 1.3),
        ]
        case .heart: [
            ("soft", "M 12 21.7 C 8.5 18.7 2 14.2 2 9.2 C 2 3.7 9 1.7 12 7.2 C 15 1.7 22 3.7 22 9.2 C 22 14.2 15.5 18.7 12 21.7 Z", 0),
            ("solid", "M 12 17.15 C 10.25 15.65 7 13.4 7 10.9 C 7 8.15 10.5 7.15 12 9.9 C 13.5 7.15 17 8.15 17 10.9 C 17 13.4 13.75 15.65 12 17.15 Z", 0),
            ("hi", "M 5.6 8.4 C 5.8 7 6.8 6 8.2 5.8", 1.3),
        ]
        case .emergency: [
            ("soft", "M 6 6 L 18 6 C 19.88 6 21.4 7.52 21.4 9.4 L 21.4 17.6 C 21.4 19.48 19.88 21 18 21 L 6 21 C 4.12 21 2.6 19.48 2.6 17.6 L 2.6 9.4 C 2.6 7.52 4.12 6 6 6 Z", 0),
            ("solid", "M 10.2 2.6 L 13.8 2.6 C 14.79 2.6 15.6 3.41 15.6 4.4 L 15.6 5.8 C 15.6 6.79 14.79 7.6 13.8 7.6 L 10.2 7.6 C 9.21 7.6 8.4 6.79 8.4 5.8 L 8.4 4.4 C 8.4 3.41 9.21 2.6 10.2 2.6 Z", 1.7),
            ("solid", "M 11.8 9.6 L 12.2 9.6 C 12.86 9.6 13.4 10.14 13.4 10.8 L 13.4 17 C 13.4 17.66 12.86 18.2 12.2 18.2 L 11.8 18.2 C 11.14 18.2 10.6 17.66 10.6 17 L 10.6 10.8 C 10.6 10.14 11.14 9.6 11.8 9.6 Z", 0),
            ("solid", "M 8.9 12.5 L 15.1 12.5 C 15.76 12.5 16.3 13.04 16.3 13.7 L 16.3 14.1 C 16.3 14.76 15.76 15.3 15.1 15.3 L 8.9 15.3 C 8.24 15.3 7.7 14.76 7.7 14.1 L 7.7 13.7 C 7.7 13.04 8.24 12.5 8.9 12.5 Z", 0),
        ]
        case .celebrate: [
            ("soft", "M 4.32 20.93 C 3.5 21.22 3.18 20.9 3.47 20.08 L 7.53 8.72 C 7.82 7.9 8.38 7.78 8.99 8.39 L 16.01 15.41 C 16.62 16.02 16.5 16.58 15.68 16.87 Z", 0),
            ("solid", "M 8 7.4 C 11.6 8.6 15.6 12.6 17 16.4 C 15.2 17.4 11.2 15 9.4 13 C 7.6 11 7 8.4 8 7.4 Z", 0),
            ("solid:F5B300", "M 18.8 4.4 C 18.8 5.17 18.17 5.8 17.4 5.8 C 16.63 5.8 16 5.17 16 4.4 C 16 3.63 16.63 3 17.4 3 C 18.17 3 18.8 3.63 18.8 4.4 Z", 0),
            ("solid:4C8DF6", "M 21.11 8.79 L 21.29 8.89 C 21.67 9.11 21.8 9.6 21.58 9.98 L 20.58 11.72 C 20.36 12.1 19.87 12.23 19.49 12.01 L 19.31 11.91 C 18.93 11.69 18.8 11.2 19.02 10.82 L 20.02 9.08 C 20.24 8.7 20.73 8.57 21.11 8.79 Z", 0),
            ("solid:3DBE6B", "M 12.19 2.14 L 12.38 2.07 C 12.79 1.92 13.25 2.14 13.4 2.55 L 14.09 4.43 C 14.24 4.85 14.02 5.31 13.61 5.46 L 13.42 5.53 C 13.01 5.68 12.55 5.46 12.4 5.05 L 11.71 3.17 C 11.56 2.75 11.78 2.29 12.19 2.14 Z", 0),
            ("solid", "M 20.6 13.8 C 20.9 15.1 20.9 15.1 22.2 15.4 C 20.9 15.7 20.9 15.7 20.6 17 C 20.3 15.7 20.3 15.7 19 15.4 C 20.3 15.1 20.3 15.1 20.6 13.8 Z", 0),
        ]
        case .illoLedger: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("solid:brand", "M 45.44 38.56 L 45.44 81.76 C 58.4 79.6 69.2 81.04 80 88.24 C 90.8 81.04 101.6 79.6 114.56 81.76 L 114.56 38.56 Z", 0),
            ("soft:brand", "M 50.48 32.08 C 61.28 30.64 71.36 32.8 80 39.28 L 80 81.76 C 71.36 76 61.28 73.84 50.48 75.28 Z", 0),
            ("soft:brand", "M 109.52 32.08 C 98.72 30.64 88.64 32.8 80 39.28 L 80 81.76 C 88.64 76 98.72 73.84 109.52 75.28 Z", 0),
            ("solid:brand", "M 58.4 45.76 L 71.36 48.64", 4.32),
            ("solid:brand", "M 58.4 55.84 L 71.36 58.72", 4.32),
            ("solid:brand", "M 96.56 44.32 C 98.2 51.32 98.2 51.32 105.2 52.96 C 98.2 54.6 98.2 54.6 96.56 61.6 C 94.92 54.6 94.92 54.6 87.92 52.96 C 94.92 51.32 94.92 51.32 96.56 44.32 Z", 0),
            ("solid:brand", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:brand", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:brand", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoMonth: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:brand", "M 59.84 31.36 L 100.16 31.36 C 106.92 31.36 112.4 36.84 112.4 43.6 L 112.4 78.88 C 112.4 85.64 106.92 91.12 100.16 91.12 L 59.84 91.12 C 53.08 91.12 47.6 85.64 47.6 78.88 L 47.6 43.6 C 47.6 36.84 53.08 31.36 59.84 31.36 Z", 0),
            ("solid:brand", "M 57.32 31.36 L 102.68 31.36 C 108.05 31.36 112.4 35.71 112.4 41.08 L 112.4 50.8 L 47.6 50.8 L 47.6 41.08 C 47.6 35.71 51.95 31.36 57.32 31.36 Z", 0),
            ("solid:brand", "M 65.96 23.44 L 65.96 23.44 C 68.15 23.44 69.92 25.21 69.92 27.4 L 69.92 36.04 C 69.92 38.23 68.15 40 65.96 40 L 65.96 40 C 63.77 40 62 38.23 62 36.04 L 62 27.4 C 62 25.21 63.77 23.44 65.96 23.44 Z", 0),
            ("solid:brand", "M 94.04 23.44 L 94.04 23.44 C 96.23 23.44 98 25.21 98 27.4 L 98 36.04 C 98 38.23 96.23 40 94.04 40 L 94.04 40 C 91.85 40 90.08 38.23 90.08 36.04 L 90.08 27.4 C 90.08 25.21 91.85 23.44 94.04 23.44 Z", 0),
            ("solid:brand", "M 80 77.69 C 76.72 74.88 70.64 70.67 70.64 65.99 C 70.64 60.84 77.19 58.97 80 64.12 C 82.81 58.97 89.36 60.84 89.36 65.99 C 89.36 70.67 83.28 74.88 80 77.69 Z", 0),
            ("solid:brand", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:brand", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:brand", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoSpending: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:brand", "M 102.45 45.04 C 108.31 55.2 106.62 68.03 98.33 76.33 C 90.03 84.62 77.2 86.31 67.04 80.45 C 56.88 74.58 51.93 62.62 54.96 51.29 C 58 39.96 68.27 32.08 80 32.08", 15.84),
            ("solid:brand", "M 80 21.28 C 95.84 21.28 109.52 32.08 113.84 46.48 L 80 58 Z", 0),
            ("solid:brand", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:brand", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:brand", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoTrends: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:ai", "M 54.8 58 L 56.96 58 C 60.94 58 64.16 61.22 64.16 65.2 L 64.16 83.2 C 64.16 87.18 60.94 90.4 56.96 90.4 L 54.8 90.4 C 50.82 90.4 47.6 87.18 47.6 83.2 L 47.6 65.2 C 47.6 61.22 50.82 58 54.8 58 Z", 0),
            ("soft:ai", "M 78.92 43.6 L 81.08 43.6 C 85.06 43.6 88.28 46.82 88.28 50.8 L 88.28 83.2 C 88.28 87.18 85.06 90.4 81.08 90.4 L 78.92 90.4 C 74.94 90.4 71.72 87.18 71.72 83.2 L 71.72 50.8 C 71.72 46.82 74.94 43.6 78.92 43.6 Z", 0),
            ("solid:ai", "M 103.04 29.2 L 105.2 29.2 C 109.18 29.2 112.4 32.42 112.4 36.4 L 112.4 83.2 C 112.4 87.18 109.18 90.4 105.2 90.4 L 103.04 90.4 C 99.06 90.4 95.84 87.18 95.84 83.2 L 95.84 36.4 C 95.84 32.42 99.06 29.2 103.04 29.2 Z", 0),
            ("solid:ai", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:ai", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:ai", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoAccounts: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("solid:F98DB0", "M 109.52 29.2 C 109.52 34.37 105.33 38.56 100.16 38.56 C 94.99 38.56 90.8 34.37 90.8 29.2 C 90.8 24.03 94.99 19.84 100.16 19.84 C 105.33 19.84 109.52 24.03 109.52 29.2 Z", 0),
            ("soft:F98DB0", "M 77.84 37.12 C 96.56 37.12 108.8 48.64 108.8 63.04 C 108.8 71.68 104.48 78.16 98.72 81.76 L 98.72 88.96 C 98.72 91.12 97.28 92.56 95.12 92.56 L 89.36 92.56 C 87.2 92.56 85.76 91.12 85.76 88.96 L 85.76 86.08 C 82.88 86.8 80 86.8 77.12 86.8 C 74.24 86.8 71.36 86.8 68.48 86.08 L 68.48 88.96 C 68.48 91.12 67.04 92.56 64.88 92.56 L 59.12 92.56 C 56.96 92.56 55.52 91.12 55.52 88.96 L 55.52 80.32 C 52.64 78.16 50.48 75.28 49.04 72.4 L 46.16 72.4 C 44 72.4 42.56 70.96 42.56 68.8 L 42.56 59.44 C 42.56 57.28 44 55.84 46.16 55.84 L 49.04 55.84 C 51.2 49.36 54.8 45.04 59.12 42.16 L 56.24 31.36 C 55.88 29.92 57.32 28.84 58.76 29.2 L 69.92 34.96 C 72.44 37.12 74.96 37.12 77.84 37.12 Z", 0),
            ("solid:F98DB0", "M 73.52 45.76 L 84.32 45.76 C 85.91 45.76 87.2 47.05 87.2 48.64 L 87.2 48.64 C 87.2 50.23 85.91 51.52 84.32 51.52 L 73.52 51.52 C 71.93 51.52 70.64 50.23 70.64 48.64 L 70.64 48.64 C 70.64 47.05 71.93 45.76 73.52 45.76 Z", 0),
            ("solid:F98DB0", "M 95.84 58 C 95.84 59.99 94.23 61.6 92.24 61.6 C 90.25 61.6 88.64 59.99 88.64 58 C 88.64 56.01 90.25 54.4 92.24 54.4 C 94.23 54.4 95.84 56.01 95.84 58 Z", 0),
            ("solid:F98DB0", "M 108.8 60.16 C 113.84 58.72 117.44 60.88 116.72 65.2 C 116 68.8 111.68 67.36 112.4 63.76", 0),
            ("hi:F98DB0", "M 100.16 24.88 L 100.16 33.52", 3.6),
            ("solid:F98DB0", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:F98DB0", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:F98DB0", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoPlans: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:income", "M 43.28 90.4 C 51.2 70.24 65.6 61.6 80 61.6 C 94.4 61.6 108.8 70.24 116.72 90.4 Z", 0),
            ("solid:income", "M 69.2 68.8 L 69.2 25.6", 6.48),
            ("solid:income", "M 72.08 24.16 L 103.04 34.24 C 105.92 35.32 105.92 38.92 103.04 40 L 72.08 50.08 Z", 0),
            ("solid:income", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:income", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:income", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoSearch: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:fg3", "M 100.88 52.24 C 100.88 66.95 88.95 78.88 74.24 78.88 C 59.53 78.88 47.6 66.95 47.6 52.24 C 47.6 37.53 59.53 25.6 74.24 25.6 C 88.95 25.6 100.88 37.53 100.88 52.24 Z", 0),
            ("solid:fg3", "M 100.88 52.24 C 100.88 66.95 88.95 78.88 74.24 78.88 C 59.53 78.88 47.6 66.95 47.6 52.24 C 47.6 37.53 59.53 25.6 74.24 25.6 C 88.95 25.6 100.88 37.53 100.88 52.24 Z", 7.92),
            ("solid:fg3", "M 94.4 72.4 L 111.68 89.68", 11.52),
            ("hi:fg3", "M 60.03 47.07 C 61.56 42.87 64.87 39.56 69.07 38.03", 5.04),
            ("solid:fg3", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:fg3", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:fg3", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoConnect: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:ai", "M 53.82 59.01 L 65.53 47.3 C 70.59 42.24 78.8 42.24 83.86 47.3 L 83.86 47.3 C 88.92 52.36 88.92 60.57 83.86 65.63 L 72.15 77.34 C 67.09 82.4 58.88 82.4 53.82 77.34 L 53.82 77.34 C 48.76 72.28 48.76 64.07 53.82 59.01 Z", 8.64),
            ("solid:ai", "M 76.14 50.37 L 87.85 38.66 C 92.91 33.6 101.12 33.6 106.18 38.66 L 106.18 38.66 C 111.24 43.72 111.24 51.93 106.18 56.99 L 94.47 68.7 C 89.41 73.76 81.2 73.76 76.14 68.7 L 76.14 68.7 C 71.08 63.64 71.08 55.43 76.14 50.37 Z", 8.64),
            ("solid:ai", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:ai", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:ai", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoError: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:warn", "M 74.71 33.58 C 77.99 27.74 82.01 27.74 85.29 33.58 L 110.71 78.82 C 113.99 84.66 111.9 88.24 105.2 88.24 L 54.8 88.24 C 48.1 88.24 46.01 84.66 49.29 78.82 Z", 0),
            ("solid:warn", "M 80 47.2 L 80 63.76", 8.64),
            ("solid:warn", "M 85.04 76 C 85.04 78.78 82.78 81.04 80 81.04 C 77.22 81.04 74.96 78.78 74.96 76 C 74.96 73.22 77.22 70.96 80 70.96 C 82.78 70.96 85.04 73.22 85.04 76 Z", 0),
            ("solid:warn", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:warn", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:warn", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoDone: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:income", "M 76.38 28.94 C 78.62 25.08 81.38 25.08 83.62 28.94 L 88.48 37.28 C 90.73 41.14 94.78 44.08 99.14 45.02 L 108.57 47.07 C 112.93 48.01 113.78 50.63 110.81 53.96 L 104.38 61.15 C 101.41 64.48 99.86 69.25 100.31 73.69 L 101.28 83.29 C 101.73 87.73 99.5 89.35 95.42 87.55 L 86.59 83.66 C 82.5 81.86 77.5 81.86 73.41 83.66 L 64.58 87.55 C 60.5 89.35 58.27 87.73 58.72 83.29 L 59.69 73.69 C 60.14 69.25 58.59 64.48 55.62 61.15 L 49.19 53.96 C 46.22 50.63 47.07 48.01 51.43 47.07 L 60.86 45.02 C 65.22 44.08 69.27 41.14 71.52 37.28 Z", 0),
            ("solid:income", "M 95.84 60.16 C 95.84 68.91 88.75 76 80 76 C 71.25 76 64.16 68.91 64.16 60.16 C 64.16 51.41 71.25 44.32 80 44.32 C 88.75 44.32 95.84 51.41 95.84 60.16 Z", 0),
            ("hi:income", "M 72.8 60.88 L 78.56 65.92 L 87.2 55.84", 5.04),
            ("solid:income", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:income", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:income", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        case .illoLoading: [
            ("ground", "M 126 106 C 126 109.31 105.41 112 80 112 C 54.59 112 34 109.31 34 106 C 34 102.69 54.59 100 80 100 C 105.41 100 126 102.69 126 106 Z", 0),
            ("soft:ai", "M 62 84.64 C 51.92 84.64 44 76.72 44 66.64 C 44 57.28 51.2 49.36 60.56 48.64 C 63.44 37.12 72.8 29.2 84.32 29.2 C 98 29.2 108.8 39.28 110.24 52.24 C 116.72 54.4 120.32 60.16 120.32 67.36 C 120.32 76.72 113.12 84.64 103.76 84.64 Z", 0),
            ("solid:ai", "M 69.31 55.48 C 71.12 50.49 75.67 47 80.97 46.53 C 86.26 46.07 91.35 48.72 94.01 53.32", 6.48),
            ("solid:ai", "M 94.67 46.41 C 95.39 45.56 96.01 45.7 96.28 46.79 L 98.28 54.81 C 98.55 55.9 98.04 56.48 96.93 56.34 L 88.99 55.34 C 87.88 55.2 87.65 54.6 88.37 53.75 Z", 0),
            ("solid:ai", "M 95.01 64.84 C 93.2 69.83 88.65 73.32 83.35 73.79 C 78.06 74.25 72.97 71.6 70.31 67", 6.48),
            ("solid:ai", "M 69.65 73.91 C 68.93 74.76 68.31 74.62 68.04 73.53 L 66.04 65.51 C 65.77 64.42 66.28 63.84 67.39 63.98 L 75.33 64.98 C 76.44 65.12 76.67 65.72 75.95 66.57 Z", 0),
            ("solid:ai", "M 126 20 C 127.14 24.86 127.14 24.86 132 26 C 127.14 27.14 127.14 27.14 126 32 C 124.86 27.14 124.86 27.14 120 26 C 124.86 24.86 124.86 24.86 126 20 Z", 0),
            ("soft:ai", "M 36 35.6 C 36.84 39.16 36.84 39.16 40.4 40 C 36.84 40.84 36.84 40.84 36 44.4 C 35.16 40.84 35.16 40.84 31.6 40 C 35.16 39.16 35.16 39.16 36 35.6 Z", 0),
            ("soft:ai", "M 122 76.6 C 122.65 79.35 122.65 79.35 125.4 80 C 122.65 80.65 122.65 80.65 122 83.4 C 121.35 80.65 121.35 80.65 118.6 80 C 121.35 79.35 121.35 79.35 122 76.6 Z", 0),
        ]
        }
    }
}

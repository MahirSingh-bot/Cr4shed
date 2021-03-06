#import "CRARootViewController.h"
#import "CRAProcViewController.h"
#import "Process.h"
#import "Log.h"
#import "../sharedutils.h"
#import "UIImage+UIKitImage.h"
#import "Cephei/HBPreferences.h"

@implementation ProcessCell
-(instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier
{
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]))
	{
		self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		
		_countLbl = [[UILabel alloc] initWithFrame:CGRectZero];
		_countLbl.font = [UIFont systemFontOfSize:15.];
		_countLbl.textColor = [UIColor whiteColor];
		_countLbl.backgroundColor = [UIColor systemRedColor];
		_countLbl.textAlignment = NSTextAlignmentCenter;
		_countLbl.numberOfLines = 1;
		_countLbl.clipsToBounds = YES;
		_countLbl.translatesAutoresizingMaskIntoConstraints = NO;

		[self.contentView addSubview:_countLbl];

		[_countLbl.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.].active = YES;
		[_countLbl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
	}
	return self;
}

-(void)updateLabels
{
	self.textLabel.text = _proc.name;
	self.detailTextLabel.text = stringFromDate(_proc.latestDate, CR4DateFormatPretty);
	_countLbl.text = [NSString stringWithFormat:@"%llu", (unsigned long long)_proc.logs.count];	

	const CGFloat badgeHeight = 20.;
	const CGFloat minBadgePadding = 10.;
	CGFloat minBadgeWidth = badgeHeight * 1.5;
	CGFloat badgeWidth = [_countLbl.text boundingRectWithSize:CGSizeZero options:NSStringDrawingUsesLineFragmentOrigin| NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName : _countLbl.font} context:nil].size.width + minBadgePadding;
	badgeWidth = MAX(badgeWidth, minBadgeWidth);

	if (_widthConstraint) _widthConstraint.active = NO;
	if (_heightConstraint) _heightConstraint.active = NO;
	_widthConstraint = [_countLbl.widthAnchor constraintEqualToConstant:badgeWidth];
	_heightConstraint = [_countLbl.heightAnchor constraintEqualToConstant:badgeHeight];
	[NSLayoutConstraint activateConstraints:@[_widthConstraint, _heightConstraint]];
	_countLbl.layer.cornerRadius = MIN(badgeHeight, badgeWidth) / 2.;
}
@end

@implementation CRARootViewController
{
	NSMutableArray<Process*>* _procs;
}

-(instancetype)init
{
	if ((self = [super init]))
	{
		//UIApplicationDidBecomeActiveNotification
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTable:) name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
		//CR4ProcsNeedRefreshNotificationName
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTable:) name:CR4ProcsNeedRefreshNotificationName object:nil];
	
		self.title = @"Cr4shed";
		UIImage* itemImg = [[UIImage uikitImageNamed:@"UIButtonBarBookmarks"] resizeToWidth:25.];
		self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Reports" image:itemImg tag:0];
	}
	return self;
}

-(void)loadView
{
	[super loadView];

	if ([self.navigationController.navigationBar respondsToSelector:@selector(setPrefersLargeTitles:)])
		self.navigationController.navigationBar.prefersLargeTitles = YES;

	self.navigationItem.rightBarButtonItem = self.editButtonItem;

	//remove extra separators
	self.tableView.tableFooterView = [UIView new];
	self.tableView.rowHeight = 50;

	//pull to refresh:
	_refreshControl = [UIRefreshControl new];
    [_refreshControl addTarget:self action:@selector(refreshTable:) forControlEvents:UIControlEventValueChanged];
	if ([self.tableView respondsToSelector:@selector(setRefreshControl:)])
        self.tableView.refreshControl = _refreshControl;
	else
        [self.tableView addSubview:_refreshControl];
}

-(void)viewDidLoad
{
	[super viewDidLoad];
	[self refreshTable:nil];
}

-(void)refreshTable:(id)obj
{
	[self loadLogs];
	if (_refreshControl.refreshing)
		[_refreshControl endRefreshing];
	[self.tableView reloadData];
}

-(void)viewDidAppear:(BOOL)arg1
{
    [super viewDidAppear:arg1];
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    self.navigationController.interactivePopGestureRecognizer.enabled = NO;
}

-(void)sortProcs
{
	NSString* sortingMethod = [[NSUserDefaults standardUserDefaults] objectForKey:kSortingMethod];
	[_procs sortUsingComparator:^NSComparisonResult(Process* a, Process* b) {
		//Date = @"Date" or nil
		//Name = @"Name"
		if ([sortingMethod isEqualToString:@"Name"])
			return [[a.name lowercaseString] compare:[b.name lowercaseString]];
		NSDate* first = a.latestDate;
	    NSDate* second = b.latestDate; 
	    return [second compare:first];
	}];
	for (int i = 0; i < _procs.count; i++)
	{
		if (_procs[i].logs.count == 0)
		{
			[_procs removeObjectAtIndex:i];
			i--;
		}
	}
}

-(void)loadLogs
{
	_procs = [NSMutableArray new];
	//loop through all logs
	NSString* const logsDirectory = @"/var/mobile/Library/Cr4shed";
	NSMutableArray* files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:logsDirectory error:nil] mutableCopy];
	for (int i = 0; i < files.count; i++)
	{
		NSString* fileName = files[i];
		NSString* filePath = [logsDirectory stringByAppendingPathComponent:fileName];
		if (![[fileName pathExtension] isEqualToString:@"log"])
		{
			[files removeObjectAtIndex:i];
			i--;
			continue;
		}
		//file is a log
		Process* proc = nil;
		NSArray<NSString*>* comp = [fileName componentsSeparatedByString:@"@"];
		NSString* procName = comp.count > 1 ? comp[0] : @"(null)";

		//check if process is already in array
		for (Process* p in _procs)
		{
			if ([p.name isEqualToString:procName])
			{
				proc = p;
				break;
			}
		}
		if (!proc)
		{
			//process isn't in array, add it
			proc = [[Process alloc] initWithName:procName];
			[_procs addObject:proc];
		}
		Log* log = [[Log alloc] initWithPath:filePath];
		[proc.logs addObject:log];

		NSDate* date = log.date;
		if (!proc.latestDate || [proc.latestDate compare:date] == NSOrderedAscending)
		{
			proc.latestDate = date;
		}
	}

	[self sortProcs];
}

-(void)deleteProcessAtIndexPath:(NSIndexPath*)indexPath
{
	Process* proc = _procs[indexPath.row];
	[proc deleteAllLogs];
	[_procs removeObjectAtIndex:indexPath.row];
	[self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Table View Data Source

-(NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
	return 1;
}

-(NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return _procs.count;
}

-(UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	ProcessCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ProcessCell"];
	if (!cell)
	{
		cell = [[ProcessCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProcessCell"];
	}
	cell.proc = _procs[indexPath.row];
	[cell updateLabels];
	return cell;
}

-(void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath*)indexPath
{
	[self deleteProcessAtIndexPath:indexPath];
}

#pragma mark - Table View Delegate

-(UISwipeActionsConfiguration*)tableView:(UITableView*)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath
{
	Process* proc = _procs[indexPath.row];
	UIContextualAction* deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL)){
		[self deleteProcessAtIndexPath:indexPath];
		completionHandler(YES);
	}];
	BOOL isBlacklisted = [proc isBlacklisted];
	NSString* blacklistTitle = isBlacklisted ? @"Un-blacklist" : @"Blacklist";
	UIContextualAction* blacklistAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:blacklistTitle handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL)){
		if (isBlacklisted)
			[proc removeFromBlacklist];
		else
			[proc addToBlacklist];
		[[NSNotificationCenter defaultCenter] postNotificationName:CR4BlacklistDidChangeNotificationName object:nil];
		completionHandler(YES);
	}];
	blacklistAction.backgroundColor = [UIColor systemBlueColor];
	NSArray<UIContextualAction*>* actions = @[deleteAction, blacklistAction];
	UISwipeActionsConfiguration* config = [UISwipeActionsConfiguration configurationWithActions:actions];
	return config;
}

-(void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	CRAProcViewController* procVC = [[CRAProcViewController alloc] initWithProcess:_procs[indexPath.row]];
	[self.navigationController pushViewController:procVC animated:YES];
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(void)setEditing:(BOOL)editing animated:(BOOL)animated
{
	[super setEditing:editing animated:animated];

	UIBarButtonItem* item = nil;
	if (editing)
	{
		item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(removeAllLogs)];
	}
	[self.navigationItem setLeftBarButtonItem:item animated:animated];
}

-(void)removeAllLogs
{
	NSMutableArray* indexPaths = [[NSMutableArray alloc] initWithCapacity:_procs.count];
	for (NSUInteger i = 0; i < _procs.count; i++)
	{
		NSIndexPath* indexPath = [NSIndexPath indexPathForRow:i inSection:0];
		Process* proc = _procs[i];
		[proc deleteAllLogs];
		[indexPaths addObject:indexPath];
	}
	_procs = [NSMutableArray new];
	[self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
